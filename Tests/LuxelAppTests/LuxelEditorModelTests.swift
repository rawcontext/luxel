import Foundation
import LuxelCore
import Testing
@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor model")
struct LuxelEditorModelTests {
    @Test("completed export shows progress panel actions")
    func completedExportShowsProgressPanelActions() async throws {
        let exportedURL = URL(fileURLWithPath: "/tmp/source Export.mp4")
        let model = makeModel(
            exporter: StubMediaExporter(exportedMedia: try exportedMedia(fileURL: exportedURL))
        )

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.showsExportProgressPanel)
        #expect(model.exportedURL == exportedURL)
        #expect(model.exportPanelTitle == "Export Complete")
        #expect(model.exportPanelSystemImage == "checkmark.circle")
        #expect(model.exportProgressValue == 1)
        #expect(model.canRetryExport)
    }

    @Test("opening a recording clears stale export progress")
    func openingRecordingClearsStaleExportProgress() async throws {
        let model = makeModel()

        model.exportProgress = .completed(format: .mp4)
        await model.open(fileURL: URL(fileURLWithPath: "/tmp/next.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.exportProgress == nil)
        #expect(!model.showsExportProgressPanel)
        #expect(model.status == .ready)
    }

    @Test("import failure clears stale export progress")
    func importFailureClearsStaleExportProgress() {
        let model = makeModel()

        model.exportProgress = .completed(format: .mp4)
        model.reportImportFailure(StubError.importFailed)

        #expect(model.exportProgress == nil)
        #expect(!model.showsExportProgressPanel)
        #expect(!model.hasSource)
    }

    @Test("save original copies source without exporting")
    func saveOriginalCopiesSourceWithoutExporting() async throws {
        let fileSystem = SpyFileSystem()
        let model = makeModel(fileSystem: fileSystem)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.saveOriginal()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/source Original.mp4")
        #expect(model.status == .saved(expectedOutputURL))
        #expect(fileSystem.createdDirectories.map(\.path) == ["/tmp"])
        #expect(fileSystem.copiedFiles == [
            CopiedFile(sourceURL: sourceURL, destinationURL: expectedOutputURL)
        ])
    }

    @Test("refreshing export estimate builds request from current editor state")
    func refreshingExportEstimateBuildsRequestFromCurrentEditorState() async throws {
        let estimator = SpyExportSizeEstimator()
        let model = makeModel(exportSizeEstimator: estimator)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setTrimStart(2)
        model.setTrimEnd(8)
        model.setOutputWidth(640)
        model.setOutputHeight(360)
        model.setFrameRate(24)
        model.setQuality(.high)
        model.setIncludesAudio(false)
        await model.refreshExportEstimate()

        let expectedEstimate = try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
        let expectedRange = try TimeRange(start: 2, end: 8)
        let expectedPixelSize = try PixelSize(width: 640, height: 360)
        let expectedFrameRate = try FrameRate(24)
        let captured = await estimator.request()

        #expect(model.exportEstimate == expectedEstimate)
        #expect(model.exportEstimateSummary == "~ 1.5 MB")
        #expect(captured?.format == .hevc)
        #expect(captured?.timeRange == expectedRange)
        #expect(captured?.pixelSize == expectedPixelSize)
        #expect(captured?.frameRate == expectedFrameRate)
        #expect(captured?.quality == .high)
        #expect(captured?.outputShouldMute == true)
    }

    @Test("format changes clamp unavailable quality")
    func formatChangesClampUnavailableQuality() {
        let model = makeModel()

        model.setQuality(.high)
        #expect(model.quality == .high)
        #expect(model.availableQualities == [.compact, .balanced, .high])

        model.setFormat(.apng)
        #expect(model.quality == .lossless)
        #expect(model.availableQualities == [.lossless])
        #expect(!model.canChooseQuality)

        model.setQuality(.balanced)
        #expect(model.quality == .lossless)
    }

    @Test("unsupported estimate clears stale value")
    func unsupportedEstimateClearsStaleValue() async throws {
        let model = makeModel(exportSizeEstimator: StubFailingExportSizeEstimator())

        model.exportEstimate = try ExportEstimate(bytes: 42, confidence: .modeled)
        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        await model.refreshExportEstimate()

        #expect(model.exportEstimate == nil)
        #expect(model.exportEstimateSummary == nil)
    }

    private func makeModel(
        exporter: any MediaExporter = StubMediaExporter(),
        exportSizeEstimator: any ExportSizeEstimator = StubExportSizeEstimator(),
        fileSystem: any FileSystem = StubFileSystem()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            metadataReader: StubMetadataReader(),
            exportService: ExportService(
                exporter: exporter,
                fileSystem: fileSystem
            ),
            exportSizeEstimationService: ExportSizeEstimationService(
                estimator: exportSizeEstimator
            ),
            passthroughExportService: PassthroughExportService(
                fileSystem: fileSystem,
                trimmedExporter: StubPassthroughExporter()
            ),
            fileWorkflowService: ExportedFileWorkflowService(
                client: StubExportedFileActionClient()
            )
        )
    }

    private func exportedMedia(fileURL: URL) throws -> ExportedMedia {
        try ExportedMedia(
            fileURL: fileURL,
            format: .mp4,
            pixelSize: PixelSize(width: 1280, height: 720),
            shouldMute: false
        )
    }
}

private enum StubError: Error {
    case importFailed
}

private struct StubMetadataReader: MediaMetadataReader {
    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        try SourceMedia(
            fileURL: fileURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
    }
}

private struct StubMediaExporter: MediaExporter {
    let exportedMedia: ExportedMedia?

    init(exportedMedia: ExportedMedia? = nil) {
        self.exportedMedia = exportedMedia
    }

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        if let exportedMedia {
            return exportedMedia
        }

        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

private struct StubPassthroughExporter: PassthroughExporter {
    func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        PassthroughExportResult(fileURL: request.outputFileURL)
    }
}

private struct StubExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }
}

private struct StubFailingExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        throw StubError.importFailed
    }
}

private actor SpyExportSizeEstimator: ExportSizeEstimator {
    private var capturedRequest: ExportRequest?

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        capturedRequest = request
        return try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }

    func request() -> ExportRequest? {
        capturedRequest
    }
}

private struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func removeFile(at url: URL) throws {}
}

private final class SpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCreatedDirectories: [URL] = []
    private var capturedCopiedFiles: [CopiedFile] = []

    var createdDirectories: [URL] {
        lock.withLock {
            capturedCreatedDirectories
        }
    }

    var copiedFiles: [CopiedFile] {
        lock.withLock {
            capturedCopiedFiles
        }
    }

    func fileExists(at url: URL) -> Bool {
        false
    }

    func createDirectory(at url: URL) throws {
        lock.withLock {
            capturedCreatedDirectories.append(url)
        }
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        lock.withLock {
            capturedCopiedFiles.append(CopiedFile(sourceURL: sourceURL, destinationURL: destinationURL))
        }
    }

    func removeFile(at url: URL) throws {}
}

private struct CopiedFile: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

@MainActor
private final class StubExportedFileActionClient: ExportedFileActionClient {
    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        nil
    }

    func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        nil
    }

    func chooseApplicationForOpening(fileURL: URL) -> URL? {
        nil
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func copyFileToPasteboard(_ fileURL: URL) {}

    func copyPathToPasteboard(_ fileURL: URL) {}

    func copyTextToPasteboard(_ text: String) {}

    func revealInFinder(_ fileURL: URL) {}

    func openWithDefaultApp(_ fileURL: URL) {}

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {}
}
