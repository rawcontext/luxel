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
        frameGrabFileWriter: SpyFrameGrabFileWriter = SpyFrameGrabFileWriter(),
        frameGrabDestinationClient: SpyFrameGrabDestinationClient = SpyFrameGrabDestinationClient(),
        audioPeakAnalyzer: any AudioPeakAnalyzer = SpyAudioPeakAnalyzer(),
        audioTranscriptService: (any AudioTranscriptService)? = nil,
        speechRecognitionAuthorizationService: (any SpeechRecognitionAuthorizationService)? =
            StubSpeechRecognitionAuthorizationService(state: .authorized),
        codecAvailability: CodecAvailability = .none,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil,
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
                fileWriter: frameGrabFileWriter,
                destinationClient: frameGrabDestinationClient
            ),
            audioPeakAnalyzer: audioPeakAnalyzer,
            audioTranscriptService: audioTranscriptService,
            speechRecognitionAuthorizationService: speechRecognitionAuthorizationService,
            fileSystem: fileSystem,
            codecAvailability: codecAvailability,
            directoryAccessService: directoryAccessService,
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

    func frameImageData() throws -> FrameGrabImageData {
        try FrameGrabImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
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

    func waitForTranscript(_ model: LuxelEditorModel) async throws -> TurnSegmentedTranscript {
        for _ in 0..<100 {
            if let transcript = model.visibleTranscript {
                return transcript
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        return try #require(model.visibleTranscript)
    }

    func sampleTranscript(source: TranscriptSourceLabel?) throws -> TurnSegmentedTranscript {
        let spans = [
            try TimedTranscriptSpan(
                id: "span-0",
                text: "Hello",
                start: 0,
                end: 0.5,
                confidence: 0.9,
                source: source
            ),
            try TimedTranscriptSpan(
                id: "span-1",
                text: "world",
                start: 0.5,
                end: 1,
                confidence: 0.9,
                source: source
            )
        ]

        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: spans.map(\.id),
                    start: 0,
                    end: 1,
                    text: "Hello world",
                    source: source
                )
            ],
            localeIdentifier: "en_US"
        )
    }

    func previewAudioVolumeRamp(for inputParameters: AVAudioMixInputParameters) -> (
        start: Float, end: Float
    )? {
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
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelEditorModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func makeRecordingFile(
        named fileName: String,
        in directory: URL,
        modificationDate: Date
    ) throws -> URL {
        let fileURL = directory.appending(path: fileName).standardizedFileURL
        try Data([0]).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: modificationDate],
            ofItemAtPath: fileURL.path
        )
        return fileURL
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
        records.append(
            Record(
                context: context,
                description: String(describing: error)
            ))
    }
}

struct StubMetadataReader: MediaMetadataReader {
    let hasAlpha: Bool
    let source: SourceMedia?

    init(hasAlpha: Bool = false, source: SourceMedia? = nil) {
        self.hasAlpha = hasAlpha
        self.source = source
    }

    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        if let source {
            return source
        }

        return try SourceMedia(
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
    private let imageData: FrameGrabImageData
    private(set) var requests: [FrameGrabRequest] = []

    init(imageData: FrameGrabImageData) {
        self.imageData = imageData
    }

    func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData {
        requests.append(request)
        return imageData
    }
}

struct StubFrameGrabber: FrameGrabber {
    func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData {
        try FrameGrabImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            pixelSize: PixelSize(width: 1, height: 1)
        )
    }
}

final class SpyFrameGrabFileWriter: FrameGrabFileWriter, @unchecked Sendable {
    struct Write: Equatable {
        let imageData: FrameGrabImageData
        let fileURL: URL
    }

    private(set) var writes: [Write] = []

    func write(_ imageData: FrameGrabImageData, to fileURL: URL) throws {
        writes.append(Write(imageData: imageData, fileURL: fileURL))
    }
}

@MainActor
final class SpyFrameGrabDestinationClient: FrameGrabDestinationClient {
    private(set) var copiedImages: [FrameGrabImageData] = []

    func copyImageToPasteboard(_ imageData: FrameGrabImageData) throws {
        copiedImages.append(imageData)
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

actor SpyAudioTranscriptService: AudioTranscriptService {
    private let transcriptResult: TurnSegmentedTranscript?
    private let transcriptError: (any Error)?
    private let delay: Duration?
    private var capturedRequests: [AudioTranscriptRequest] = []

    init(
        transcript: TurnSegmentedTranscript? = nil,
        error: (any Error)? = nil,
        delay: Duration? = nil
    ) {
        self.transcriptResult = transcript
        self.transcriptError = error
        self.delay = delay
    }

    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript? {
        capturedRequests.append(request)
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let transcriptError {
            throw transcriptError
        }

        return transcriptResult
    }

    func requests() -> [AudioTranscriptRequest] {
        capturedRequests
    }
}

actor StubSpeechRecognitionAuthorizationService: SpeechRecognitionAuthorizationService {
    private var state: SpeechRecognitionAuthorizationState
    private let requestedState: SpeechRecognitionAuthorizationState
    private var requestCount = 0

    init(
        state: SpeechRecognitionAuthorizationState,
        requestedState: SpeechRecognitionAuthorizationState? = nil
    ) {
        self.state = state
        self.requestedState = requestedState ?? state
    }

    func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState {
        state
    }

    func requestAuthorization() async -> SpeechRecognitionAuthorizationState {
        requestCount += 1
        state = requestedState
        return state
    }

    func requests() -> Int {
        requestCount
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
    private(set) var openedURLs: [URL] = []

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

    func openWithDefaultApp(_ fileURL: URL) {
        openedURLs.append(fileURL)
    }

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {}
}
