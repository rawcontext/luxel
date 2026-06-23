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
        #expect(requests.map(\.source) == [.system, .microphone])
        #expect(requests.map(\.audioTrackIndex) == [0, 1])
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
        let span = try TimedTranscriptSpan(
            id: "span-0",
            text: "Cached",
            start: 0,
            end: 0.5,
            source: source
        )

        return try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: [span.id],
                    start: span.start,
                    end: span.end,
                    text: span.text,
                    source: source
                )
            ],
            localeIdentifier: "en_US"
        )
    }
}

private actor SpyTimedSpeechTranscriber: TimedSpeechTranscriber {
    private(set) var requests: [TimedSpeechTranscriptionRequest] = []

    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws -> [TimedTranscriptSpan] {
        requests.append(request)
        let index = requests.count - 1
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
    let audioTrackCount: Int

    func audioTrackCount(in audioURL: URL) async throws -> Int {
        audioTrackCount
    }
}
