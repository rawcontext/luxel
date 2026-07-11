import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    func makeModel(
        metadataReader: any MediaMetadataReader = StubMetadataReader(),
        exporter: any MediaExporter = StubMediaExporter(),
        audioPreparer: any ExportAudioPreparing = StubExportAudioPreparer(),
        exportSizeEstimator: any ExportSizeEstimator = StubExportSizeEstimator(),
        fileSystem: any FileSystem = StubFileSystem(),
        fileActionClient: any ExportedFileActionClient = StubExportedFileActionClient(),
        frameGrabber: any FrameGrabber = StubFrameGrabber(),
        frameGrabFileWriter: SpyFrameGrabFileWriter = SpyFrameGrabFileWriter(),
        frameGrabDestinationClient: SpyFrameGrabDestinationClient = SpyFrameGrabDestinationClient(),
        audioPeakAnalyzer: any AudioPeakAnalyzer = SpyAudioPeakAnalyzer(),
        audioTranscriptService: (any AudioTranscriptService)? = nil,
        speechRecognitionAuthorizationService: (any SpeechRecognitionAuthorizationService)? =
            StubSpeechAuthorizationService(state: .authorized),
        codecAvailability: CodecAvailability = .none,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil,
        exportMemory: [ExportFormat: ExportMemory] = [:],
        lastSelectedExportFormat: ExportFormat? = nil,
        onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil,
        onLastSelectedExportFormatChange: (@MainActor (ExportFormat) -> Void)? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            metadataReader: metadataReader,
            exportService: ExportService(
                exporter: exporter,
                audioPreparer: audioPreparer,
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
            lastSelectedExportFormat: lastSelectedExportFormat,
            onExportMemoryChange: onExportMemoryChange,
            onLastSelectedExportFormatChange: onLastSelectedExportFormatChange,
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

@MainActor
final class SpyFrameGrabDestinationClient: FrameGrabDestinationClient {
    private(set) var copiedImages: [FrameGrabImageData] = []

    func copyImageToPasteboard(_ imageData: FrameGrabImageData) throws {
        copiedImages.append(imageData)
    }
}
