import Foundation

public struct ExportService: Sendable {
    public typealias ProgressHandler = @Sendable (ExportProgressSnapshot) async -> Void
    public typealias BatchProgressHandler = @Sendable (ExportBatchProgressSnapshot) async -> Void

    private let exporter: any MediaExporter
    private let audioPreparer: any ExportAudioPreparing
    private let fileSystem: (any FileSystem)?

    public init(
        exporter: any MediaExporter,
        audioPreparer: any ExportAudioPreparing = UnavailableExportAudioPreparer(),
        fileSystem: (any FileSystem)? = nil
    ) {
        self.exporter = exporter
        self.audioPreparer = audioPreparer
        self.fileSystem = fileSystem
    }

    public func export(
        _ draft: EditorExportDraft,
        to outputDirectory: URL,
        defaultName: String,
        progress: ProgressHandler? = nil
    ) async throws -> ExportedMedia {
        let request = try draft.exportRequest
        return try await export(
            request,
            to: outputDirectory,
            defaultName: defaultName,
            progress: progress
        )
    }

    public func export(
        _ request: ExportRequest,
        to outputDirectory: URL,
        defaultName: String,
        progress: ProgressHandler? = nil
    ) async throws -> ExportedMedia {
        let outputURL = outputDirectory.appending(
            path: request.outputFileName(defaultName: defaultName))
        let cleanup = ExportOutputCleanup(fileSystem: fileSystem, outputURL: outputURL)

        await progress?(.preparing(format: request.format))

        return try await withTaskCancellationHandler {
            do {
                let preparedAudio = try await audioPreparer.prepareAudio(
                    for: [request]
                ) { update in
                    let value = update.progress
                    if request.shouldApplyStudioVoice {
                        await progress?(
                            .enhancingAudio(format: request.format, progress: value)
                        )
                    } else {
                        await progress?(
                            ExportProgressSnapshot(
                                phase: .preparing,
                                actionTitle: "Preparing \(request.format.prettyName)",
                                progress: value
                            )
                        )
                    }
                }
                defer { preparedAudio.removeTemporaryFiles() }

                try Task.checkCancellation()
                await progress?(.exporting(format: request.format, progress: 0))

                let exported = try await exporter.export(
                    MediaExportInput(
                        request: request,
                        preparedAudio: preparedAudio.asset(forRequestAt: 0)
                    ),
                    to: outputURL
                ) { value in
                    await progress?(
                        .exporting(
                            format: request.format,
                            progress: Self.clampedProgress(value)
                        )
                    )
                }
                let exportedWithFileSize = exported.withFileSizeBytes(fileSizeBytes(at: exported.fileURL))

                try Task.checkCancellation()
                await progress?(.completed(format: request.format))
                return exportedWithFileSize
            } catch is CancellationError {
                cleanup.removeOutput()
                await progress?(.canceled(format: request.format))
                throw CancellationError()
            } catch {
                cleanup.removeOutput()
                throw error
            }
        } onCancel: {
            cleanup.removeOutput()
        }
    }

    public func runBatch(
        _ batch: ExportBatch,
        to outputDirectory: URL,
        defaultName: String,
        progress: BatchProgressHandler? = nil
    ) async throws -> [ExportedMedia] {
        var exportedByJobID = [ExportedMedia?](repeating: nil, count: batch.requests.count)

        for (jobID, request) in batch.requests.enumerated() {
            await progress?(
                ExportBatchProgressSnapshot(
                    jobID: jobID,
                    snapshot: .preparing(format: request.format)
                )
            )
        }

        let preparedAudio = try await audioPreparer.prepareAudio(
            for: batch.requests
        ) { update in
            for jobID in update.requestIndices {
                let request = batch.requests[jobID]
                let snapshot: ExportProgressSnapshot
                if request.shouldApplyStudioVoice {
                    snapshot = .enhancingAudio(
                        format: request.format,
                        progress: update.progress
                    )
                } else {
                    snapshot = ExportProgressSnapshot(
                        phase: .preparing,
                        actionTitle: "Preparing \(request.format.prettyName)",
                        progress: update.progress
                    )
                }
                await progress?(
                    ExportBatchProgressSnapshot(jobID: jobID, snapshot: snapshot)
                )
            }
        }
        defer { preparedAudio.removeTemporaryFiles() }

        try await withThrowingTaskGroup(of: (jobID: Int, exported: ExportedMedia).self) { group in
            var nextJobID = 0

            func addJob(_ jobID: Int) {
                let request = batch.requests[jobID]
                group.addTask {
                    let exported = try await exportPrepared(
                        request,
                        preparedAudio: preparedAudio.asset(forRequestAt: jobID),
                        to: outputDirectory,
                        defaultName: batchDefaultName(defaultName, format: request.format)
                    ) { snapshot in
                        await progress?(ExportBatchProgressSnapshot(jobID: jobID, snapshot: snapshot))
                    }
                    return (jobID, exported)
                }
            }

            while nextJobID < min(batch.requests.count, Self.maxConcurrentBatchJobs) {
                addJob(nextJobID)
                nextJobID += 1
            }

            while let result = try await group.next() {
                exportedByJobID[result.jobID] = result.exported

                if nextJobID < batch.requests.count {
                    addJob(nextJobID)
                    nextJobID += 1
                }
            }
        }

        return exportedByJobID.compactMap { $0 }
    }

    private func exportPrepared(
        _ request: ExportRequest,
        preparedAudio: PreparedAudioAsset?,
        to outputDirectory: URL,
        defaultName: String,
        progress: ProgressHandler?
    ) async throws -> ExportedMedia {
        let outputURL = outputDirectory.appending(
            path: request.outputFileName(defaultName: defaultName)
        )
        let cleanup = ExportOutputCleanup(fileSystem: fileSystem, outputURL: outputURL)

        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                await progress?(.exporting(format: request.format, progress: 0))
                let exported = try await exporter.export(
                    MediaExportInput(request: request, preparedAudio: preparedAudio),
                    to: outputURL
                ) { value in
                    await progress?(
                        .exporting(
                            format: request.format,
                            progress: Self.clampedProgress(value)
                        )
                    )
                }
                let result = exported.withFileSizeBytes(fileSizeBytes(at: exported.fileURL))
                try Task.checkCancellation()
                await progress?(.completed(format: request.format))
                return result
            } catch is CancellationError {
                cleanup.removeOutput()
                await progress?(.canceled(format: request.format))
                throw CancellationError()
            } catch {
                cleanup.removeOutput()
                throw error
            }
        } onCancel: {
            cleanup.removeOutput()
        }
    }

    private static let maxConcurrentBatchJobs = 4

    private func batchDefaultName(_ defaultName: String, format: ExportFormat) -> String {
        "\(defaultName) \(batchNameComponent(for: format))"
    }

    private func batchNameComponent(for format: ExportFormat) -> String {
        switch format {
        case .gif:
            "GIF"
        case .hevc:
            "HEVC"
        case .mp4:
            "H.264"
        case .proRes422:
            "ProRes 422"
        case .proRes4444:
            "ProRes 4444"
        case .av1:
            "AV1"
        case .webm:
            "WebM"
        case .apng:
            "APNG"
        case .m4a:
            "M4A AAC"
        case .alac:
            "M4A ALAC"
        case .wav:
            "WAV"
        case .caf:
            "CAF"
        case .flac:
            "FLAC"
        }
    }

    private func fileSizeBytes(at fileURL: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }

        return size.int64Value
    }

    private static func clampedProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

private final class ExportOutputCleanup: @unchecked Sendable {
    private let fileSystem: (any FileSystem)?
    private let outputURL: URL
    private let lock = NSLock()
    private var didRemoveOutput = false

    init(fileSystem: (any FileSystem)?, outputURL: URL) {
        self.fileSystem = fileSystem
        self.outputURL = outputURL
    }

    func removeOutput() {
        lock.lock()
        let shouldRemove = !didRemoveOutput
        didRemoveOutput = true
        lock.unlock()

        guard shouldRemove else {
            return
        }

        try? fileSystem?.removeFile(at: outputURL)
    }
}
