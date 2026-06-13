import Foundation
import LuxelCore
import Testing

@Suite("Export service")
struct ExportServiceTests {
    @Test("service exports draft to named destination")
    func serviceExportsDraftToNamedDestination() async throws {
        let exporter = SpyMediaExporter()
        let service = ExportService(exporter: exporter)
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let draft = EditorExportDraft(source: source, format: .hevc)

        let result = try await service.export(
            draft,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        )
        let expectedPixelSize = try PixelSize(width: 640, height: 480)

        #expect(result.fileURL.path == "/tmp/exports/Luxel Clip.mp4")
        #expect(result.format == .hevc)
        #expect(result.pixelSize == expectedPixelSize)
        #expect(result.shouldMute == false)

        let captured = await exporter.capturedExport()
        #expect(captured?.request.format == .hevc)
        #expect(captured?.outputFileURL.path == "/tmp/exports/Luxel Clip.mp4")
    }

    @Test("service emits progress snapshots")
    func serviceEmitsProgressSnapshots() async throws {
        let exporter = SpyMediaExporter()
        let progress = ProgressRecorder()
        let service = ExportService(exporter: exporter)
        let source = try makeSource()
        let draft = EditorExportDraft(source: source, format: .gif)

        _ = try await service.export(
            draft,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        ) { snapshot in
            await progress.append(snapshot)
        }

        let snapshots = await progress.snapshots()

        #expect(snapshots == [
            .preparing(format: .gif),
            .exporting(format: .gif, progress: 0.05),
            .completed(format: .gif)
        ])
    }

    @Test("service removes intended output when export task is canceled")
    func serviceRemovesIntendedOutputWhenExportTaskIsCanceled() async throws {
        let exporter = CancellableMediaExporter()
        let fileSystem = SpyFileSystem()
        let service = ExportService(exporter: exporter, fileSystem: fileSystem)
        let source = try makeSource()
        let draft = EditorExportDraft(source: source, format: .mp4)
        let outputDirectory = URL(fileURLWithPath: "/tmp/exports")
        let expectedOutputURL = outputDirectory.appending(path: "Luxel Clip.mp4")

        let task = Task {
            try await service.export(
                draft,
                to: outputDirectory,
                defaultName: "Luxel Clip"
            )
        }

        await exporter.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(fileSystem.removedURLs == [expectedOutputURL])
    }

    private func makeSource() throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
    }
}

private actor SpyMediaExporter: MediaExporter {
    private var captured: (request: ExportRequest, outputFileURL: URL)?

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        captured = (request, outputFileURL)
        return try ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExport() -> (request: ExportRequest, outputFileURL: URL)? {
        captured
    }
}

private actor ProgressRecorder {
    private var captured: [ExportProgressSnapshot] = []

    func append(_ snapshot: ExportProgressSnapshot) {
        captured.append(snapshot)
    }

    func snapshots() -> [ExportProgressSnapshot] {
        captured
    }
}

private actor CancellableMediaExporter: MediaExporter {
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        markStarted()

        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func markStarted() {
        started = true
        startContinuation?.resume()
        startContinuation = nil
    }
}

private final class SpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRemovedURLs: [URL] = []

    var removedURLs: [URL] {
        lock.withLock {
            capturedRemovedURLs
        }
    }

    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func removeFile(at url: URL) throws {
        lock.withLock {
            capturedRemovedURLs.append(url)
        }
    }
}
