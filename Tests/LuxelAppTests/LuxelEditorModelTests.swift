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

    @Test("discard recording trashes source and clears editor")
    func discardRecordingTrashesSourceAndClearsEditor() async throws {
        let fileSystem = SpyFileSystem()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        var discardedURLs: [URL] = []
        let model = makeModel(fileSystem: fileSystem)
        model.configureDiscard(confirmDiscard: false) { fileURL in
            discardedURLs.append(fileURL)
        }

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.discardRecording()

        #expect(fileSystem.trashedFiles == [sourceURL])
        #expect(discardedURLs == [sourceURL])
        #expect(!model.hasSource)
        #expect(!model.canDiscard)
        #expect(model.status == .discarded("source.mp4"))
        #expect(model.statusMessage == "Discarded source.mp4")
    }

    @Test("discard recording keeps source when trash fails")
    func discardRecordingKeepsSourceWhenTrashFails() async throws {
        let fileSystem = SpyFileSystem(trashError: StubError.trashFailed)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        var discardedURLs: [URL] = []
        let model = makeModel(fileSystem: fileSystem)
        model.configureDiscard(confirmDiscard: false) { fileURL in
            discardedURLs.append(fileURL)
        }

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.discardRecording()

        #expect(fileSystem.trashedFiles == [sourceURL])
        #expect(discardedURLs.isEmpty)
        #expect(model.hasSource)

        if case .failed = model.status {
        } else {
            Issue.record("Expected discard failure status")
        }
    }

    @Test("discard confirmation setting emits changes")
    func discardConfirmationSettingEmitsChanges() {
        var capturedSettings: [Bool] = []
        let model = makeModel()
        model.configureDiscard(
            confirmDiscard: true,
            onConfirmDiscardChange: { confirmDiscard in
                capturedSettings.append(confirmDiscard)
            }
        )

        model.setConfirmDiscard(false)
        model.setConfirmDiscard(false)
        model.setConfirmDiscard(true)

        #expect(model.confirmDiscard)
        #expect(capturedSettings == [false, true])
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

    @Test("format selection keeps at least one format")
    func formatSelectionKeepsAtLeastOneFormat() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        model.setFormatSelection(.mp4, isSelected: false)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.selectedFormatSummary == "MP4 (H264)")

        model.setFormatSelection(.gif, isSelected: true)
        #expect(model.selectedFormats == [.mp4, .gif])
        #expect(model.format == .gif)
        #expect(model.selectedFormatSummary == "2 Formats")

        model.setFormatSelection(.gif, isSelected: false)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.format == .mp4)
    }

    @Test("export memory seeds controls when opening and changing formats")
    func exportMemorySeedsControlsWhenOpeningAndChangingFormats() async throws {
        let memory: [ExportFormat: ExportMemory] = [
            .mp4: try ExportMemory(
                sizePreset: .percent50,
                frameRate: FrameRate(24),
                quality: .high
            ),
            .gif: try ExportMemory(
                sizePreset: .percent25,
                frameRate: FrameRate(12),
                quality: .compact
            ),
            .apng: try ExportMemory(
                sizePreset: .percent75,
                frameRate: FrameRate(120),
                quality: .balanced
            )
        ]
        let model = makeModel(exportMemory: memory)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(model.outputHeight == 360)
        #expect(model.frameRate == 24)
        #expect(model.quality == .high)

        model.setFormat(.gif)

        #expect(model.sizePreset == .percent25)
        #expect(model.outputWidth == 320)
        #expect(model.outputHeight == 180)
        #expect(model.frameRate == 12)
        #expect(model.quality == .compact)

        model.setFormat(.apng)

        #expect(model.sizePreset == .percent75)
        #expect(model.outputWidth == 960)
        #expect(model.outputHeight == 540)
        #expect(model.frameRate == 30)
        #expect(model.quality == .lossless)
    }

    @Test("successful export emits format memory")
    func successfulExportEmitsFormatMemory() async throws {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setSizePreset(.percent50)
        model.setFrameRate(24)
        model.setQuality(.high)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(24),
            quality: .high
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .hevc)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("batch export runs selected formats and exposes job rows")
    func batchExportRunsSelectedFormatsAndExposesJobRows() async throws {
        let exporter = SpyMediaExporter()
        var rememberedFormats: [ExportFormat] = []
        let model = makeModel(exporter: exporter) { format, _ in
            rememberedFormats.append(format)
        }

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormatSelection(.hevc, isSelected: true)
        model.setFormatSelection(.gif, isSelected: true)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()

        #expect(captured.map(\.request.format) == [.mp4, .hevc, .gif])
        #expect(captured.map(\.outputFileURL.path) == [
            "/tmp/source Export H264.mp4",
            "/tmp/source Export H265.mp4",
            "/tmp/source Export GIF.gif"
        ])
        #expect(model.status == .exportedBatch([
            URL(fileURLWithPath: "/tmp/source Export H264.mp4"),
            URL(fileURLWithPath: "/tmp/source Export H265.mp4"),
            URL(fileURLWithPath: "/tmp/source Export GIF.gif")
        ]))
        #expect(model.exportPanelMessage == "3 files exported")
        #expect(model.exportProgressValue == 1)
        #expect(model.exportJobs.map(\.format) == [.mp4, .hevc, .gif])
        #expect(model.exportJobs.map(\.statusSummary) == ["Complete", "Complete", "Complete"])
        #expect(model.exportJobs.compactMap(\.fileURL).map(\.path) == [
            "/tmp/source Export H264.mp4",
            "/tmp/source Export H265.mp4",
            "/tmp/source Export GIF.gif"
        ])
        #expect(rememberedFormats == [.mp4, .hevc, .gif])
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
        fileSystem: any FileSystem = StubFileSystem(),
        exportMemory: [ExportFormat: ExportMemory] = [:],
        onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil
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
            ),
            fileSystem: fileSystem,
            exportMemory: exportMemory,
            onExportMemoryChange: onExportMemoryChange
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
    case trashFailed
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

private actor SpyMediaExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        captured.append((request, outputFileURL))
        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExports() -> [(request: ExportRequest, outputFileURL: URL)] {
        captured
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

    func trashItem(at url: URL) throws {}
}

private final class SpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCreatedDirectories: [URL] = []
    private var capturedCopiedFiles: [CopiedFile] = []
    private var capturedTrashedFiles: [URL] = []
    private let trashError: Error?

    init(trashError: Error? = nil) {
        self.trashError = trashError
    }

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

    var trashedFiles: [URL] {
        lock.withLock {
            capturedTrashedFiles
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

    func trashItem(at url: URL) throws {
        lock.withLock {
            capturedTrashedFiles.append(url)
        }

        if let trashError {
            throw trashError
        }
    }
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
