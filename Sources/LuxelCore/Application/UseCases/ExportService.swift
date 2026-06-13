import Foundation

public struct ExportService: Sendable {
    public typealias ProgressHandler = @Sendable (ExportProgressSnapshot) async -> Void

    private let exporter: any MediaExporter
    private let fileSystem: (any FileSystem)?

    public init(exporter: any MediaExporter, fileSystem: (any FileSystem)? = nil) {
        self.exporter = exporter
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
        let outputURL = outputDirectory.appending(path: request.outputFileName(defaultName: defaultName))
        let cleanup = ExportOutputCleanup(fileSystem: fileSystem, outputURL: outputURL)

        await progress?(.preparing(format: request.format))

        return try await withTaskCancellationHandler {
            do {
                try Task.checkCancellation()
                await progress?(.exporting(format: request.format, progress: 0.05))

                let exported = try await exporter.export(request, to: outputURL)

                try Task.checkCancellation()
                await progress?(.completed(format: request.format))
                return exported
            } catch is CancellationError {
                cleanup.removeOutput()
                await progress?(.canceled(format: request.format))
                throw CancellationError()
            } catch {
                throw error
            }
        } onCancel: {
            cleanup.removeOutput()
        }
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
