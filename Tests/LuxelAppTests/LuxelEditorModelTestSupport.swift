import AVFoundation
import Foundation
import LuxelCore
import Testing
@testable import LuxelPresentation

extension LuxelEditorModelTests {
    func makeModel(
        metadataReader: any MediaMetadataReader = StubMetadataReader(),
        exporter: any MediaExporter = StubMediaExporter(),
        exportSizeEstimator: any ExportSizeEstimator = StubExportSizeEstimator(),
        fileSystem: any FileSystem = StubFileSystem(),
        fileActionClient: any ExportedFileActionClient = StubExportedFileActionClient(),
        frameGrabber: any FrameGrabber = StubFrameGrabber(),
        screenshotFileWriter: SpyScreenshotFileWriter = SpyScreenshotFileWriter(),
        screenshotDestinationClient: SpyScreenshotDestinationClient = SpyScreenshotDestinationClient(),
        audioPeakAnalyzer: any AudioPeakAnalyzer = SpyAudioPeakAnalyzer(),
        codecAvailability: CodecAvailability = .none,
        exportMemory: [ExportFormat: ExportMemory] = [:],
        onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            metadataReader: metadataReader,
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
                client: fileActionClient
            ),
            frameGrabService: FrameGrabService(
                frameGrabber: frameGrabber,
                fileWriter: screenshotFileWriter,
                destinationClient: screenshotDestinationClient
            ),
            audioPeakAnalyzer: audioPeakAnalyzer,
            fileSystem: fileSystem,
            codecAvailability: codecAvailability,
            exportMemory: exportMemory,
            onExportMemoryChange: onExportMemoryChange,
            errorReporter: errorReporter
        )
    }

    func exportedMedia(fileURL: URL) throws -> ExportedMedia {
        try ExportedMedia(
            fileURL: fileURL,
            format: .mp4,
            pixelSize: PixelSize(width: 1280, height: 720),
            shouldMute: false
        )
    }

    func frameImageData() throws -> ImageData {
        try ImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            format: .png,
            pixelSize: PixelSize(width: 2, height: 2)
        )
    }

    func waitForPreviewAudioMix(_ model: LuxelEditorModel) async throws -> AVAudioMix {
        for _ in 0..<100 {
            if let audioMix = model.player.currentItem?.audioMix {
                return audioMix
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return try #require(model.player.currentItem?.audioMix)
    }

    func previewAudioVolumeRamp(for inputParameters: AVAudioMixInputParameters) -> (start: Float, end: Float)? {
        var startVolume: Float = 0
        var endVolume: Float = 0
        var timeRange = CMTimeRange.invalid
        let foundRamp = inputParameters.getVolumeRamp(
            for: .zero,
            startVolume: &startVolume,
            endVolume: &endVolume,
            timeRange: &timeRange
        )

        guard foundRamp else {
            return nil
        }

        return (startVolume, endVolume)
    }

    func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }

    func isApproximately(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double = 0.000_001
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}

enum StubError: Error {
    case importFailed
    case trashFailed
}

final class SpyErrorReporter: ErrorReporter {
    struct Record: Equatable {
        let context: String
        let description: String
    }

    private(set) var records: [Record] = []

    func record(_ error: any Error, context: String) {
        records.append(Record(
            context: context,
            description: String(describing: error)
        ))
    }
}

struct StubMetadataReader: MediaMetadataReader {
    let hasAlpha: Bool

    init(hasAlpha: Bool = false) {
        self.hasAlpha = hasAlpha
    }

    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        try SourceMedia(
            fileURL: fileURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true,
            hasAlpha: hasAlpha
        )
    }
}

struct StubMediaExporter: MediaExporter {
    let exportedMedia: ExportedMedia?

    init(exportedMedia: ExportedMedia? = nil) {
        self.exportedMedia = exportedMedia
    }

    func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
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

actor SpyMediaExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []

    func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
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

struct StubPassthroughExporter: PassthroughExporter {
    func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        PassthroughExportResult(fileURL: request.outputFileURL)
    }
}

final class SpyFrameGrabber: FrameGrabber, @unchecked Sendable {
    private let imageData: ImageData
    private(set) var requests: [FrameGrabRequest] = []

    init(imageData: ImageData) {
        self.imageData = imageData
    }

    func grab(_ request: FrameGrabRequest) async throws -> ImageData {
        requests.append(request)
        return imageData
    }
}

struct StubFrameGrabber: FrameGrabber {
    func grab(_ request: FrameGrabRequest) async throws -> ImageData {
        try ImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            format: .png,
            pixelSize: PixelSize(width: 1, height: 1)
        )
    }
}

final class SpyScreenshotFileWriter: ScreenshotFileWriter, @unchecked Sendable {
    struct Write: Equatable {
        let imageData: ImageData
        let fileURL: URL
    }

    private(set) var writes: [Write] = []

    func write(_ imageData: ImageData, to fileURL: URL) throws {
        writes.append(Write(imageData: imageData, fileURL: fileURL))
    }
}

@MainActor
final class SpyScreenshotDestinationClient: ScreenshotDestinationClient {
    private(set) var copiedImages: [ImageData] = []
    private(set) var openedURLs: [URL] = []

    func copyImageToPasteboard(_ imageData: ImageData) throws {
        copiedImages.append(imageData)
    }

    func openWithDefaultApp(_ fileURL: URL) throws {
        openedURLs.append(fileURL)
    }
}

struct StubExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }
}

struct StubFailingExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        throw StubError.importFailed
    }
}

actor SpyAudioPeakAnalyzer: AudioPeakAnalyzer {
    private var capturedRequests: [AudioPeakAnalysisRequest] = []
    private let peaks: [AudioTrackKind: Double]

    init(peaks: [AudioTrackKind: Double] = [:]) {
        self.peaks = peaks
    }

    func measurePeaks(_ request: AudioPeakAnalysisRequest) async throws -> [AudioTrackKind: Double] {
        capturedRequests.append(request)
        return peaks
    }

    func requests() -> [AudioPeakAnalysisRequest] {
        capturedRequests
    }
}

actor SpyExportSizeEstimator: ExportSizeEstimator {
    private var capturedRequest: ExportRequest?

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        capturedRequest = request
        return try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }

    func request() -> ExportRequest? {
        capturedRequest
    }
}

struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

final class SpyFileSystem: FileSystem, @unchecked Sendable {
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

    func writeData(_ data: Data, to url: URL) throws {}

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

struct CopiedFile: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

@MainActor
final class StubExportedFileActionClient: ExportedFileActionClient {
    let saveDestination: URL?
    private(set) var requestedSaveNames: [String] = []

    init(saveDestination: URL? = nil) {
        self.saveDestination = saveDestination
    }

    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        requestedSaveNames.append(suggestedFileName)
        return saveDestination
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
