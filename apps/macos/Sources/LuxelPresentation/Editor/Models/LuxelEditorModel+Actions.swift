import AVKit
import Foundation
import LuxelCore
import Observation

private struct EditorExportOperation: Sendable {
    let requests: [ExportRequest]
    let memoryByFormat: [ExportFormat: ExportMemory]
    let service: ExportService
    let outputDirectory: URL
    let outputDirectoryBookmark: BookmarkedDirectory?
    let directoryAccessService: BookmarkedDirectoryAccessService?
    let defaultName: String
    let fileSystem: any FileSystem
}

extension LuxelEditorModel {
    func navigateToOlderRecording() async {
        guard let recordingNavigationIndex,
              canNavigateToOlderRecording
        else {
            return
        }

        await openRecordingNavigationItem(at: recordingNavigationIndex + 1)
    }

    func navigateToNewerRecording() async {
        guard let recordingNavigationIndex,
              canNavigateToNewerRecording
        else {
            return
        }

        await openRecordingNavigationItem(at: recordingNavigationIndex - 1)
    }

    private func openRecordingNavigationItem(at index: Int) async {
        guard recordingNavigationURLs.indices.contains(index) else {
            return
        }

        await open(
            fileURL: recordingNavigationURLs[index],
            outputDirectory: outputDirectory,
            outputDirectoryBookmark: outputDirectoryBookmark
        )
    }

    func refreshExportEstimate() async {
        guard let source else {
            exportEstimatesByFormat = [:]
            estimatingExportSizeFormats = []
            return
        }

        let taskID = exportEstimateTaskID
        let formats = supportedFormats
        exportEstimatesByFormat = [:]
        estimatingExportSizeFormats = Set(formats)
        defer {
            if exportEstimateTaskID == taskID {
                estimatingExportSizeFormats = []
            }
        }

        do {
            for format in formats {
                guard !Task.isCancelled, exportEstimateTaskID == taskID else {
                    return
                }

                do {
                    let request = try makeExportRequest(source: source, format: format)
                    let estimate = try await exportSizeEstimationService.estimate(request)
                    guard !Task.isCancelled, exportEstimateTaskID == taskID else {
                        return
                    }

                    exportEstimatesByFormat[format] = estimate
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    guard !Task.isCancelled, exportEstimateTaskID == taskID else {
                        return
                    }

                    exportEstimatesByFormat.removeValue(forKey: format)
                }
                estimatingExportSizeFormats.remove(format)
            }
        } catch is CancellationError {
            return
        } catch {
            exportEstimatesByFormat = [:]
        }
    }

    func startExport() {
        guard canExport, let source else {
            return
        }

        guard exportTask == nil else {
            return
        }

        status = .exporting
        let selectedFormats = selectedFormats
        exportJobs = makeExportJobs(for: selectedFormats)
        exportProgress = .preparing(format: format)

        do {
            let operation = EditorExportOperation(
                requests: try selectedFormats.map { selectedFormat in
                    try makeExportRequest(source: source, format: selectedFormat)
                },
                memoryByFormat: try Dictionary(
                    uniqueKeysWithValues: selectedFormats.map { selectedFormat in
                        (selectedFormat, try currentExportMemory(for: selectedFormat))
                    }
                ),
                service: exportService,
                outputDirectory: outputDirectory,
                outputDirectoryBookmark: outputDirectoryBookmark,
                directoryAccessService: directoryAccessService,
                defaultName: defaultExportName(for: source.fileURL),
                fileSystem: fileSystem
            )

            exportTask = Task { [weak self] in
                await self?.performExport(operation)
            }
        } catch {
            status = .failed(errorMessage(error))
            exportProgress = nil
        }
    }

    private func performExport(_ operation: EditorExportOperation) async {
        do {
            try await withExportDirectoryAccess(
                outputDirectory: operation.outputDirectory,
                bookmark: operation.outputDirectoryBookmark,
                directoryAccessService: operation.directoryAccessService
            ) { [weak self] resolvedOutputDirectory in
                guard let self else {
                    throw CancellationError()
                }
                try await self.executeExport(operation, in: resolvedOutputDirectory)
            }
        } catch is CancellationError {
            finishCanceledExport()
        } catch {
            finishFailedExport(error)
        }
    }

    private func executeExport(
        _ operation: EditorExportOperation,
        in resolvedOutputDirectory: URL
    ) async throws {
        let exportOutputDirectory =
            operation.requests.count > 1
            ? editorBatchOutputDirectory(
                defaultName: operation.defaultName,
                in: resolvedOutputDirectory
            )
            : resolvedOutputDirectory
        try operation.fileSystem.createDirectory(at: exportOutputDirectory)

        if operation.requests.count == 1, let request = operation.requests.first {
            try await exportSingleRequest(request, operation: operation, to: exportOutputDirectory)
        } else {
            try await exportBatch(operation, to: exportOutputDirectory)
        }
    }

    private func exportSingleRequest(
        _ request: ExportRequest,
        operation: EditorExportOperation,
        to outputDirectory: URL
    ) async throws {
        let exported = try await operation.service.export(
            request,
            to: outputDirectory,
            defaultName: operation.defaultName
        ) { [weak self] snapshot in
            await self?.handleSingleExportProgress(snapshot)
        }
        finishExport(
            with: exported,
            remembering: operation.memoryByFormat[exported.format]
        )
    }

    private func exportBatch(
        _ operation: EditorExportOperation,
        to outputDirectory: URL
    ) async throws {
        let batch = try ExportBatch(operation.requests)
        let exported = try await operation.service.runBatch(
            batch,
            to: outputDirectory,
            defaultName: operation.defaultName
        ) { [weak self] snapshot in
            await self?.handleBatchExportProgress(snapshot)
        }
        finishBatchExport(with: exported, remembering: operation.memoryByFormat)
    }

    func saveOriginal() {
        guard let source else {
            return
        }

        guard exportTask == nil else {
            return
        }

        status = .savingOriginal
        exportProgress = nil

        let passthroughExportService = passthroughExportService
        let inputFileURL = source.fileURL
        let outputDirectory = outputDirectory
        let outputDirectoryBookmark = outputDirectoryBookmark
        let directoryAccessService = directoryAccessService

        exportTask = Task { [weak self] in
            do {
                try await withExportDirectoryAccess(
                    outputDirectory: outputDirectory,
                    bookmark: outputDirectoryBookmark,
                    directoryAccessService: directoryAccessService
                ) { resolvedOutputDirectory in
                    let request = PassthroughExportRequest(
                        inputFileURL: inputFileURL,
                        outputFileURL: editorOriginalOutputURL(for: inputFileURL, in: resolvedOutputDirectory)
                    )
                    let result = try await passthroughExportService.export(request)

                    await MainActor.run {
                        self?.finishSavedOriginal(result.fileURL)
                    }
                }
            } catch {
                await MainActor.run {
                    self?.finishFailedExport(error)
                }
            }
        }
    }

    func copyCurrentFrame() {
        guard canGrabFrame else {
            return
        }

        startFrameGrab(destinations: [.clipboard])
    }

    func saveCurrentFrameAs() {
        guard canGrabFrame else {
            return
        }

        do {
            let request = try makeCurrentFrameGrabRequest()
            guard
                let destinationURL = fileWorkflowService.chooseSaveDestination(
                    suggestedFileName: request.suggestedFileName
                )
            else {
                return
            }

            startFrameGrab(
                request: request,
                destinations: [.file],
                outputFileURL: destinationURL
            )
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func renameSourceFile(to proposedFileName: String) {
        guard let source else {
            return
        }

        do {
            let destinationURL = try renamedSourceURL(
                for: source.fileURL,
                proposedFileName: proposedFileName
            )
            guard destinationURL.standardizedFileURL != source.fileURL.standardizedFileURL else {
                return
            }
            guard !fileSystem.fileExists(at: destinationURL) else {
                throw EditorSourceRenameError.destinationExists(destinationURL)
            }

            let currentTime = currentFrameTime
            let wasPlaying = playbackRequested
            try withSourceDirectoryAccess(for: source.fileURL) {
                try fileSystem.moveFile(from: source.fileURL, to: destinationURL)
            }

            let renamedSource = try source.replacingFileURL(destinationURL)
            self.source = renamedSource
            refreshRecordingNavigation(selectedFileURL: destinationURL, outputDirectory: outputDirectory)

            let item = AVPlayerItem(url: destinationURL)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            player.seek(
                to: CMTime(seconds: currentTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            schedulePreviewAudioMixUpdate()
            if wasPlaying {
                startPlayback()
            }
            try onSourceFileRenamed?(source.fileURL, destinationURL)
            status = .ready
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    @discardableResult
    func discardRecording() -> Bool {
        guard canDiscard, let source else {
            return false
        }

        do {
            let fileURL = source.fileURL
            try fileSystem.trashItem(at: fileURL)
            clearSource()
            status = .discarded(fileURL.lastPathComponent)
            onDiscardRecording?(fileURL)
            return true
        } catch {
            status = .failed(errorMessage(error))
            return false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func retryExport() {
        guard canRetryExport else {
            return
        }

        startExport()
    }
}
