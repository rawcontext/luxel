import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {

    func chooseOutputDirectory() {
        guard
            let directory = fileWorkflowService.chooseOutputDirectory(currentDirectory: outputDirectory)
        else {
            return
        }

        outputDirectory = directory
        outputDirectoryBookmark = nil
    }

    func saveExportedFileAs() {
        guard let exportedURL else {
            return
        }

        do {
            if let savedURL = try fileWorkflowService.saveAs(exportedURL) {
                status = .saved(savedURL)
            }
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func revealExportedFile() {
        guard let exportedURL else {
            return
        }

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.revealInFinder(exportedURL)
        }
    }

    func openExportedFile() {
        guard let exportedOpenURL else {
            return
        }

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.openWithDefaultApp(exportedOpenURL)
        }
    }

    func openExportedFileWithApplication() {
        guard let exportedURL else {
            return
        }

        _ = fileWorkflowService.openWithApplication(exportedURL)
    }

    func copyExportedFilePath() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.copyPath(exportedURL)
    }

    func copyExportedFile() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.copyFile(exportedURL)
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func transcriptExtractionElapsedTime(at date: Date) -> String? {
        guard let transcriptExtractionStartedAt else {
            return nil
        }

        return formatTime(max(0, date.timeIntervalSince(transcriptExtractionStartedAt)))
    }

    func defaultExportName(for fileURL: URL) -> String {
        "\(fileURL.deletingPathExtension().lastPathComponent) Export"
    }

    func batchOutputDirectory(defaultName: String, in outputDirectory: URL) -> URL {
        editorBatchOutputDirectory(defaultName: defaultName, in: outputDirectory)
    }

    func originalOutputURL(for fileURL: URL) -> URL {
        editorOriginalOutputURL(for: fileURL, in: outputDirectory)
    }

    static var defaultRecordingsDirectory: URL {
        let moviesDirectory =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

    func handleSingleExportProgress(_ snapshot: ExportProgressSnapshot) {
        exportProgress = snapshot
        updateExportJob(id: 0, snapshot: snapshot)
    }

    func handleBatchExportProgress(_ batchSnapshot: ExportBatchProgressSnapshot) {
        updateExportJob(id: batchSnapshot.jobID, snapshot: batchSnapshot.snapshot)

        let jobCount = max(exportJobs.count, 1)
        let progress = exportJobs.reduce(0) { $0 + $1.progressValue } / Double(jobCount)
        exportProgress = ExportProgressSnapshot(
            phase: batchSnapshot.snapshot.phase,
            actionTitle: batchSnapshot.snapshot.actionTitle,
            progress: progress
        )
    }

    func finishExport(with exported: ExportedMedia, remembering exportMemory: ExportMemory?) {
        exportTask = nil
        if let exportMemory {
            rememberExportMemory(exportMemory, for: exported.format)
        }
        updateExportJob(id: 0, exported: exported)
        exportProgress = .completed(format: exported.format)
        status = .exported(exported.fileURL)
    }

    func finishBatchExport(
        with exportedMedia: [ExportedMedia],
        remembering exportMemoryByFormat: [ExportFormat: ExportMemory]
    ) {
        exportTask = nil

        for exported in exportedMedia {
            if let exportMemory = exportMemoryByFormat[exported.format] {
                rememberExportMemory(exportMemory, for: exported.format)
            }
            updateExportJob(format: exported.format, exported: exported)
        }

        exportProgress = ExportProgressSnapshot(
            phase: .completed,
            actionTitle: "Exported \(exportedMedia.count) files",
            progress: 1
        )
        status = .exportedBatch(exportedMedia.map(\.fileURL))
    }

    func finishSavedOriginal(_ fileURL: URL) {
        exportTask = nil
        exportProgress = nil
        exportJobs = []
        status = .saved(fileURL)
    }

    func finishCanceledExport() {
        exportTask = nil
        if exportProgress?.phase != .canceled {
            exportProgress = ExportProgressSnapshot(
                phase: .canceled,
                actionTitle: "Canceled Export",
                progress: 1
            )
        }
        status = .canceled
    }

    func finishFailedExport(_ error: Error) {
        exportTask = nil
        exportProgress = nil
        status = .failed(errorMessage(error))
    }

    func startFrameGrab(destinations: [FrameGrabDestination]) {
        do {
            try startFrameGrab(
                request: makeCurrentFrameGrabRequest(),
                destinations: destinations
            )
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func startFrameGrab(
        request: FrameGrabRequest,
        destinations: [FrameGrabDestination],
        outputFileURL: URL? = nil
    ) {
        do {
            let job = try FrameGrabJob(
                request: request,
                destinations: destinations,
                outputFileURL: outputFileURL
            )
            let frameGrabService = frameGrabService
            status = destinations.contains(.clipboard) ? .copyingFrame : .savingFrame

            frameGrabTask = Task { [weak self] in
                do {
                    let result = try await frameGrabService.grab(job)
                    await MainActor.run {
                        self?.finishFrameGrab(result)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.finishCanceledFrameGrab()
                    }
                } catch {
                    await MainActor.run {
                        self?.finishFailedFrameGrab(error)
                    }
                }
            }
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func finishFrameGrab(_ result: FrameGrabResult) {
        frameGrabTask = nil

        if !result.failedDestinations.isEmpty {
            status = .failed("Frame destination failed")
            return
        }

        if let fileURL = result.fileURL {
            status = .savedFrame(fileURL)
        } else if result.completedDestinations.contains(.clipboard) {
            status = .copiedFrame
        } else {
            status = .ready
        }
    }

    func finishCanceledFrameGrab() {
        frameGrabTask = nil
        status = .ready
    }

    func finishFailedFrameGrab(_ error: Error) {
        frameGrabTask = nil
        status = .failed(errorMessage(error))
    }

    func makeCurrentFrameGrabRequest() throws -> FrameGrabRequest {
        guard let source else {
            throw FrameGrabError.invalidFrameTime
        }

        return try FrameGrabRequest(
            sourceFileURL: source.fileURL,
            time: currentFrameTime
        )
    }

    var currentFrameTime: TimeInterval {
        if !transcriptEditPlan.cuts.isEmpty {
            return currentPlaybackTime
        }
        let seconds = CMTimeGetSeconds(player.currentTime())
        let finiteSeconds = seconds.isFinite ? seconds : trimStart
        return min(max(finiteSeconds, 0), max(duration, 0))
    }

    func clearSource() {
        source = nil
        studioVoiceEnabled = false
        recordingNavigationIndex = nil
        exportProgress = nil
        exportJobs = []
        exportEstimatesByFormat = [:]
        estimatingExportSizeFormats = []
        frameGrabTask?.cancel()
        frameGrabTask = nil
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        previewCompositionTask?.cancel()
        previewCompositionTask = nil
        transcript = nil
        transcriptEditPlan = .empty
        selectedTranscriptWordIDs = []
        transcriptWordSelectionAnchorID = nil
        transcriptEditStatusMessage = nil
        isEditedPreviewReady = true
        isTranscriptExtractionActive = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        speechRecognitionAuthorizationState = nil
        player.pause()
        playbackRequested = false
        currentPlaybackTime = 0
        player.replaceCurrentItem(with: nil)
        resetEditorUndoStack()
    }

}
