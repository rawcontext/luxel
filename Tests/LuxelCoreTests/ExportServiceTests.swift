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

    @Test("service records actual output file size")
    func serviceRecordsActualOutputFileSize() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luxel-export-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let exporter = WritingMediaExporter(byteCount: 1_234)
        let service = ExportService(exporter: exporter)

        let exported = try await service.export(
            try makeRequest(format: .mp4),
            to: directory,
            defaultName: "Luxel Clip"
        )

        #expect(exported.fileSizeBytes == 1_234)
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

    @Test("batch export runs requests sequentially with keyed progress")
    func batchExportRunsSequentiallyWithKeyedProgress() async throws {
        let exporter = SpyMediaExporter()
        let progress = BatchProgressRecorder()
        let service = ExportService(exporter: exporter)
        let batch = try ExportBatch([
            makeRequest(format: .mp4),
            makeRequest(format: .hevc),
            makeRequest(format: .gif)
        ])

        let exported = try await service.runBatch(
            batch,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        ) { snapshot in
            await progress.append(snapshot)
        }

        let captured = await exporter.capturedExports()
        let snapshots = await progress.snapshots()

        #expect(exported.map(\.format) == [.mp4, .hevc, .gif])
        #expect(captured.map(\.request.format) == [.mp4, .hevc, .gif])
        #expect(captured.map(\.outputFileURL.path) == [
            "/tmp/exports/Luxel Clip H264.mp4",
            "/tmp/exports/Luxel Clip H265.mp4",
            "/tmp/exports/Luxel Clip GIF.gif"
        ])
        #expect(snapshots.map(\.jobID) == [0, 0, 0, 1, 1, 1, 2, 2, 2])
        #expect(snapshots.map(\.snapshot) == [
            .preparing(format: .mp4),
            .exporting(format: .mp4, progress: 0.05),
            .completed(format: .mp4),
            .preparing(format: .hevc),
            .exporting(format: .hevc, progress: 0.05),
            .completed(format: .hevc),
            .preparing(format: .gif),
            .exporting(format: .gif, progress: 0.05),
            .completed(format: .gif)
        ])
    }

    @Test("batch cancellation keeps completed output and removes in-flight output")
    func batchCancellationKeepsCompletedOutputAndRemovesInFlightOutput() async throws {
        let exporter = CancellableBatchMediaExporter()
        let fileSystem = SpyFileSystem()
        let service = ExportService(exporter: exporter, fileSystem: fileSystem)
        let batch = try ExportBatch([
            makeRequest(format: .mp4),
            makeRequest(format: .gif),
            makeRequest(format: .hevc)
        ])

        let task = Task {
            try await service.runBatch(
                batch,
                to: URL(fileURLWithPath: "/tmp/exports"),
                defaultName: "Luxel Clip"
            )
        }

        await exporter.waitUntilSecondExportStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let captured = await exporter.capturedExports()
        #expect(captured.map(\.request.format) == [.mp4, .gif])
        #expect(fileSystem.removedURLs == [
            URL(fileURLWithPath: "/tmp/exports/Luxel Clip GIF.gif")
        ])
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

    private func makeRequest(format: ExportFormat) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: false,
            shouldCrop: false
        )
    }
}

private actor SpyMediaExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        captured.append((request, outputFileURL))
        return try ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExport() -> (request: ExportRequest, outputFileURL: URL)? {
        captured.last
    }

    func capturedExports() -> [(request: ExportRequest, outputFileURL: URL)] {
        captured
    }
}

private struct WritingMediaExporter: MediaExporter {
    let byteCount: Int

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        let data = Data(repeating: 0x5A, count: byteCount)
        try data.write(to: outputFileURL)
        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
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

private actor BatchProgressRecorder {
    private var captured: [ExportBatchProgressSnapshot] = []

    func append(_ snapshot: ExportBatchProgressSnapshot) {
        captured.append(snapshot)
    }

    func snapshots() -> [ExportBatchProgressSnapshot] {
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

private actor CancellableBatchMediaExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []
    private var secondExportStarted = false
    private var secondExportContinuation: CheckedContinuation<Void, Never>?

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        captured.append((request, outputFileURL))

        if captured.count == 1 {
            return try ExportedMedia(
                fileURL: outputFileURL,
                format: request.format,
                pixelSize: request.outputPixelSize,
                shouldMute: request.outputShouldMute
            )
        }

        markSecondExportStarted()

        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilSecondExportStarted() async {
        if secondExportStarted {
            return
        }

        await withCheckedContinuation { continuation in
            secondExportContinuation = continuation
        }
    }

    func capturedExports() -> [(request: ExportRequest, outputFileURL: URL)] {
        captured
    }

    private func markSecondExportStarted() {
        secondExportStarted = true
        secondExportContinuation?.resume()
        secondExportContinuation = nil
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

    func trashItem(at url: URL) throws {}
}
