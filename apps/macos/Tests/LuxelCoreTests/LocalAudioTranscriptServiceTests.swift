import Foundation
import LuxelCore
import Testing

@Suite("Local audio transcript service")
struct LocalAudioTranscriptServiceTests {
    @Test("service transcribes separate system and microphone tracks with source labels")
    func serviceTranscribesSeparateSourceTracks() async throws {
        let transcriber = SpyTimedSpeechTranscriber()
        let service = LocalAudioTranscriptService(
            transcriber: transcriber,
            turnSegmenter: EchoTranscriptTurnSegmenter(),
            cache: MemoryTranscriptCache(),
            audioTrackInspector: StubAudioTrackInspector(audioTrackCount: 2)
        )

        let transcript = try await service.transcript(
            for: AudioTranscriptRequest(
                audioURL: URL(fileURLWithPath: "/tmp/recording.mp4"),
                locale: Locale(identifier: "en_US"),
                sourceContext: TranscriptSourceContext(
                    recordingAudioMode: .systemAndMicrophone(deviceID: nil)
                )
            ))

        #expect(transcript?.turns.map(\.source) == [.system, .microphone])
        let requests = await transcriber.requests
        #expect(Set(requests.map(\.source)) == [.system, .microphone])
        #expect(Set(requests.map(\.audioTrackIndex)) == [0, 1])
    }

    @Test("service removes system audio echoed into the microphone transcript")
    func serviceRemovesCrossSourceEcho() async throws {
        let service = LocalAudioTranscriptService(
            transcriber: AcousticEchoTimedSpeechTranscriber(),
            turnSegmenter: EchoTranscriptTurnSegmenter(),
            cache: MemoryTranscriptCache(),
            audioTrackInspector: StubAudioTrackInspector(audioTrackCount: 2)
        )

        let transcript = try #require(
            try await service.transcript(
                for: AudioTranscriptRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/acoustic-echo.mp4"),
                    locale: Locale(identifier: "en_US"),
                    sourceContext: TranscriptSourceContext(
                        recordingAudioMode: .systemAndMicrophone(deviceID: nil)
                    )
                )
            )
        )

        #expect(transcript.spans.map(\.text) == ["This", "works.", "Yes", "Okay", "Okay"])
        #expect(
            transcript.spans.map(\.source) == [
                .system, .system, .microphone, .system, .microphone
            ]
        )
    }

    @Test("service follows marked track layout when physical order differs")
    func serviceFollowsMarkedTrackLayout() async throws {
        let transcriber = SpyTimedSpeechTranscriber()
        let service = LocalAudioTranscriptService(
            transcriber: transcriber,
            turnSegmenter: EchoTranscriptTurnSegmenter(),
            cache: MemoryTranscriptCache(),
            audioTrackInspector: StubAudioTrackInspector(
                audioTrackLayout: AudioTrackLayout(trackKinds: [.microphone, .system])
            )
        )

        let transcript = try await service.transcript(
            for: AudioTranscriptRequest(
                audioURL: URL(fileURLWithPath: "/tmp/reordered-recording.mp4"),
                locale: Locale(identifier: "en_US"),
                sourceContext: TranscriptSourceContext(
                    recordingAudioMode: .systemAndMicrophone(deviceID: nil)
                )
            ))

        #expect(transcript?.turns.map(\.source) == [.microphone, .system])
        let requests = await transcriber.requests
        let trackIndexBySource = Dictionary(
            uniqueKeysWithValues: requests.compactMap { request in
                request.source.map { ($0, request.audioTrackIndex) }
            }
        )
        #expect(trackIndexBySource[.system] == 1)
        #expect(trackIndexBySource[.microphone] == 0)
    }

    @Test("service returns cached transcript without transcribing")
    func serviceReturnsCachedTranscript() async throws {
        let cachedTranscript = try sampleTranscript(source: .microphone)
        let cache = MemoryTranscriptCache(cachedTranscript: cachedTranscript)
        let transcriber = SpyTimedSpeechTranscriber()
        let service = LocalAudioTranscriptService(
            transcriber: transcriber,
            turnSegmenter: EchoTranscriptTurnSegmenter(),
            cache: cache,
            audioTrackInspector: StubAudioTrackInspector(audioTrackCount: 1)
        )

        let transcript = try await service.transcript(
            for: AudioTranscriptRequest(
                audioURL: URL(fileURLWithPath: "/tmp/cached.m4a"),
                locale: Locale(identifier: "en_US"),
                sourceContext: TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil))
            ))

        #expect(transcript == cachedTranscript)
        #expect(await transcriber.requests.isEmpty)
    }

    @Test("service can return raw transcript without semantic turn segmentation")
    func serviceCanReturnRawTranscriptWithoutSemanticTurnSegmentation() async throws {
        let cache = MemoryTranscriptCache()
        let transcriber = SpyTimedSpeechTranscriber()
        let service = LocalAudioTranscriptService(
            transcriber: transcriber,
            turnSegmenter: FailingTranscriptTurnSegmenter(),
            turnSegmentationMode: { .raw },
            cache: cache,
            audioTrackInspector: StubAudioTrackInspector(audioTrackCount: 1)
        )

        let transcript = try await service.transcript(
            for: AudioTranscriptRequest(
                audioURL: URL(fileURLWithPath: "/tmp/raw.m4a"),
                locale: Locale(identifier: "en_US"),
                sourceContext: TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil))
            ))

        #expect(transcript?.turns.map(\.text) == ["Microphone"])
        #expect(cache.savedRequests.map(\.turnSegmentationMode) == [.raw])
    }

    private func sampleTranscript(source: TranscriptSourceLabel?) throws -> TurnSegmentedTranscript {
        try sampleTestTranscript(text: "Cached", source: source)
    }
}

private struct AcousticEchoTimedSpeechTranscriber: TimedSpeechTranscriber {
    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws
        -> [TimedTranscriptSpan] {
        switch request.source {
        case .system:
            try [
                span("system-this", "This", 10, 10.24, source: .system),
                span("system-works", "works.", 10.24, 10.72, source: .system),
                span("system-okay", "Okay", 12, 12.3, source: .system)
            ]
        case .microphone:
            try [
                span("microphone-this", "this", 10.06, 10.3, source: .microphone),
                span("microphone-works", "works", 10.3, 10.78, source: .microphone),
                span("microphone-yes", "Yes", 10.5, 10.9, source: .microphone),
                span("microphone-okay", "Okay", 13, 13.3, source: .microphone)
            ]
        case nil:
            []
        }
    }

    private func span(
        _ id: String,
        _ text: String,
        _ start: TimeInterval,
        _ end: TimeInterval,
        source: TranscriptSourceLabel
    ) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            source: source
        )
    }
}

private actor SpyTimedSpeechTranscriber: TimedSpeechTranscriber {
    private(set) var requests: [TimedSpeechTranscriptionRequest] = []

    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws -> [TimedTranscriptSpan] {
        requests.append(request)
        let index = request.audioTrackIndex ?? 0
        let text = request.source == .system ? "System" : "Microphone"
        let start = TimeInterval(index)

        return [
            try TimedTranscriptSpan(
                id: "temporary-\(index)",
                text: text,
                start: start,
                end: start + 0.5,
                source: request.source
            )
        ]
    }
}

private struct EchoTranscriptTurnSegmenter: TranscriptTurnSegmenter {
    func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            candidates: spans.enumerated().map { index, span in
                TranscriptTurnCandidate(
                    id: "turn-\(index)",
                    spanIDs: [span.id],
                    start: span.start,
                    end: span.end,
                    text: span.text,
                    source: span.source
                )
            },
            localeIdentifier: locale.identifier
        )
    }
}

private struct FailingTranscriptTurnSegmenter: TranscriptTurnSegmenter {
    func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        throw TranscriptModelError.invalidTranscript
    }
}

private final class MemoryTranscriptCache: TranscriptCache, @unchecked Sendable {
    private let cachedTranscript: TurnSegmentedTranscript?
    private(set) var savedTranscripts: [TurnSegmentedTranscript] = []
    private(set) var savedRequests: [AudioTranscriptRequest] = []

    init(cachedTranscript: TurnSegmentedTranscript? = nil) {
        self.cachedTranscript = cachedTranscript
    }

    func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript? {
        cachedTranscript
    }

    func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest) throws {
        savedTranscripts.append(transcript)
        savedRequests.append(request)
    }
}

private struct StubAudioTrackInspector: AudioTrackInspector {
    let audioTrackLayout: AudioTrackLayout

    init(audioTrackCount: Int) {
        self.audioTrackLayout = AudioTrackLayout(audioTrackCount: audioTrackCount)
    }

    init(audioTrackLayout: AudioTrackLayout) {
        self.audioTrackLayout = audioTrackLayout
    }

    func audioTrackCount(in audioURL: URL) async throws -> Int {
        audioTrackLayout.count
    }

    func audioTrackLayout(in audioURL: URL) async throws -> AudioTrackLayout {
        audioTrackLayout
    }
}
