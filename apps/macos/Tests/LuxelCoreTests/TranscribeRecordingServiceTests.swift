import Foundation
import LuxelCore
import Testing

@Suite("Transcribe recording service")
struct TranscribeRecordingServiceTests {
    @Test("transcribe forwards request progress and builds caption track")
    func transcribeForwardsRequestProgressAndBuildsCaptionTrack() async throws {
        let audioURL = URL(fileURLWithPath: "/tmp/recording.m4a")
        let progressRecorder = ProgressRecorder()
        let words = [
            try RecognizedWord(start: 1, duration: 0.2, text: "Hello", confidence: 0.95),
            try RecognizedWord(start: 1.3, duration: 0.3, text: "world.", confidence: 0.9)
        ]
        let transcriber = SpySpeechTranscriber(
            result: SpeechTranscriptionResult(words: words, language: Locale.LanguageCode("en")),
            progressSnapshots: [
                SpeechTranscriptionProgress(fractionCompleted: 0.25),
                SpeechTranscriptionProgress(fractionCompleted: 1.2)
            ]
        )
        let service = TranscribeRecordingService(transcriber: transcriber)

        let result = try await service.transcribe(
            TranscribeRecordingRequest(
                audioURL: audioURL,
                preferredLanguage: Locale.LanguageCode("en"),
                sourceTrack: .microphone
            ),
            progress: { progressRecorder.append($0) }
        )

        let expectedTrack = try CaptionTrack(
            cues: [
                CaptionCue(timeRange: TimeRange(start: 1, end: 1.8), text: "Hello world.")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .microphone
        )
        #expect(result == TranscribedRecording(track: expectedTrack))
        #expect(
            transcriber.requests == [
                SpeechTranscriptionRequest(
                    audioURL: audioURL,
                    preferredLanguage: Locale.LanguageCode("en"),
                    sourceTrack: .microphone
                )
            ])
        #expect(
            progressRecorder.snapshots == [
                SpeechTranscriptionProgress(fractionCompleted: 0.2375),
                SpeechTranscriptionProgress(fractionCompleted: 0.95),
                SpeechTranscriptionProgress(fractionCompleted: 1)
            ])
    }

    @Test("transcribe persists captions when recording bundle is supplied")
    func transcribePersistsCaptionsWhenRecordingBundleIsSupplied() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeTranscriptionFileSystem()
        let bundle = RecordingBundle(rootURL: rootURL, manifest: try BundleManifest())
        let transcriber = SpySpeechTranscriber(
            result: SpeechTranscriptionResult(
                words: [
                    try RecognizedWord(start: 0, duration: 0.4, text: "Saved.", confidence: 0.9)
                ],
                language: Locale.LanguageCode("en")
            ))
        let service = TranscribeRecordingService(
            transcriber: transcriber,
            sidecarPersistence: CaptionSidecarPersistenceService(fileSystem: fileSystem)
        )

        let result = try await service.transcribe(
            TranscribeRecordingRequest(
                audioURL: URL(fileURLWithPath: "/tmp/recording.m4a"),
                sourceTrack: .system,
                recordingBundle: bundle
            ))

        let updatedBundle = try #require(result.updatedBundle)
        #expect(
            updatedBundle.manifest.sidecar(for: .captions) == (try BundleSidecarManifest(kind: .captions))
        )
        #expect(
            fileSystem.writtenData.map(\.url) == [
                rootURL.appendingPathComponent("captions.json"),
                rootURL.appendingPathComponent("bundle.json")
            ])

        let document = try JSONDecoder().decode(
            CaptionSidecarDocument.self,
            from: try #require(fileSystem.writtenData.first?.data)
        )
        #expect(document.track == result.track)
        #expect(result.track.sourceTrack == .system)
    }
}

private final class SpySpeechTranscriber: SpeechTranscriber, @unchecked Sendable {
    private let lock = NSLock()
    private let result: SpeechTranscriptionResult
    private let progressSnapshots: [SpeechTranscriptionProgress]
    private var capturedRequests: [SpeechTranscriptionRequest] = []

    init(
        result: SpeechTranscriptionResult,
        progressSnapshots: [SpeechTranscriptionProgress] = []
    ) {
        self.result = result
        self.progressSnapshots = progressSnapshots
    }

    var requests: [SpeechTranscriptionRequest] {
        lock.withLock {
            capturedRequests
        }
    }

    func transcribe(
        _ request: SpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> SpeechTranscriptionResult {
        lock.withLock {
            capturedRequests.append(request)
        }

        progressSnapshots.forEach(progress)
        return result
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedSnapshots: [SpeechTranscriptionProgress] = []

    var snapshots: [SpeechTranscriptionProgress] {
        lock.withLock {
            capturedSnapshots
        }
    }

    func append(_ progress: SpeechTranscriptionProgress) {
        lock.withLock {
            capturedSnapshots.append(progress)
        }
    }
}

private final class FakeTranscriptionFileSystem: FileSystem, @unchecked Sendable {
    private(set) var writtenData: [WrittenData] = []

    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {
        writtenData.append(WrittenData(data: data, url: url))
    }

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

private struct WrittenData: Equatable {
    let data: Data
    let url: URL
}
