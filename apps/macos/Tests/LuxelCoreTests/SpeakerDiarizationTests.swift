import Foundation
import Testing

@testable import LuxelCore

// MARK: - Service orchestration

@Suite("Local audio transcript service diarization")
struct TranscriptServiceDiarizationTests {
    @Test("does not call diarizer or model store when diarization is disabled")
    func doesNotDiarizeWhenDisabled() async throws {
        let diarizer = SpySpeakerDiarizer(segments: [])
        let modelStore = StubSpeakerModelStore(initiallyReady: true)
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .disabled
        )

        let transcript = try await service.transcript(for: makeRequest())

        #expect(transcript != nil)
        #expect(transcript?.speakers.isEmpty == true)
        let diarizeCalls = await diarizer.requests.count
        #expect(diarizeCalls == 0)
        let prepareCalls = await modelStore.prepareCallCount
        #expect(prepareCalls == 0)
    }

    @Test("prepares model runs diarizer and labels turns when enabled")
    func diarizesWhenEnabled() async throws {
        let diarizer = SpySpeakerDiarizer(
            segments: [
                SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 0.6)
            ],
            embeddings: ["speaker-0": [1, 0, 0]]
        )
        let modelStore = StubSpeakerModelStore(initiallyReady: false)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )

        let transcript = try await service.transcript(for: makeRequest())

        let prepareCalls = await modelStore.prepareCallCount
        #expect(prepareCalls == 1)
        let diarizeCalls = await diarizer.requests.count
        #expect(diarizeCalls == 1)
        #expect(transcript?.speakers.map(\.displayName) == ["Speaker 1"])
        #expect(transcript?.turns.compactMap(\.speakerID) == ["speaker-0"])

        let savedRequests = cache.savedRequests
        #expect(savedRequests.count == 1)
        #expect(savedRequests.first?.speakerDiarizationMode == .enabled)
        #expect(savedRequests.first?.speakerModelRevision == StubSpeakerModelStore.revision)
    }

    @Test("passes speaker count hints through diarization and cache")
    func passesSpeakerCountHintsThroughDiarizationAndCache() async throws {
        let diarizer = SpySpeakerDiarizer(
            segments: [
                SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 0.6)
            ]
        )
        let modelStore = StubSpeakerModelStore(initiallyReady: true)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )

        _ = try await service.transcript(for: makeRequest(speakerCountHint: .exact(5)))

        let requests = await diarizer.requests
        #expect(requests.first?.speakerCountHint == .exact(5))
        #expect(cache.savedRequests.first?.speakerCountHint == .exact(5))
    }

    @Test("returns non-diarized transcript under the non-diarized key when diarization fails")
    func fallsBackWhenDiarizationFails() async throws {
        let diarizer = FailingSpeakerDiarizer()
        let modelStore = StubSpeakerModelStore(initiallyReady: true)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )

        let transcript = try await service.transcript(for: makeRequest())

        #expect(transcript != nil)
        #expect(transcript?.speakers.isEmpty == true)
        let savedRequests = cache.savedRequests
        #expect(savedRequests.count == 1)
        #expect(savedRequests.first?.speakerDiarizationMode == .disabled)
        #expect(savedRequests.first?.speakerModelRevision == nil)
    }

    @Test("model preparation failure also falls back to a non-diarized transcript")
    func fallsBackWhenModelPreparationFails() async throws {
        let diarizer = SpySpeakerDiarizer(segments: [])
        let modelStore = StubSpeakerModelStore(initiallyReady: false, prepareFails: true)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )

        let transcript = try await service.transcript(for: makeRequest())

        #expect(transcript != nil)
        let diarizeCalls = await diarizer.requests.count
        #expect(diarizeCalls == 0)
        #expect(cache.savedRequests.first?.speakerDiarizationMode == .disabled)
    }

    @Test("empty diarization output produces an unlabeled transcript under the diarized key")
    func emptyDiarizationKeepsTranscriptUnlabeled() async throws {
        let diarizer = SpySpeakerDiarizer(segments: [])
        let modelStore = StubSpeakerModelStore(initiallyReady: true)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: diarizer,
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )

        let transcript = try await service.transcript(for: makeRequest())

        #expect(transcript?.speakers.isEmpty == true)
        #expect(cache.savedRequests.first?.speakerDiarizationMode == .enabled)
    }

    @Test("stores caller-updated transcripts under the effective request key")
    func storesUpdatedTranscriptUnderEffectiveKey() async throws {
        let modelStore = StubSpeakerModelStore(initiallyReady: true)
        let cache = KeyedMemoryTranscriptCache()
        let service = makeService(
            diarizer: SpySpeakerDiarizer(segments: []),
            modelStore: modelStore,
            mode: .enabled,
            cache: cache
        )
        let span = try TimedTranscriptSpan(id: "span-0", text: "Manual", start: 0, end: 1)
        let transcript = try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                try TranscriptTurn(
                    id: "turn-0", spanIDs: [span.id], start: 0, end: 1, text: span.text)
            ],
            localeIdentifier: "en_US"
        )

        try await service.storeUpdatedTranscript(transcript, for: makeRequest())

        #expect(cache.savedRequests.count == 1)
        #expect(cache.savedRequests.first?.speakerDiarizationMode == .enabled)
        #expect(cache.savedRequests.first?.speakerModelRevision == StubSpeakerModelStore.revision)
    }

    // MARK: Helpers

    private func makeRequest(
        speakerCountHint: TranscriptSpeakerCountHint = .automatic
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: URL(fileURLWithPath: "/tmp/diarized-recording.m4a"),
            locale: Locale(identifier: "en_US"),
            sourceContext: TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil)),
            speakerCountHint: speakerCountHint
        )
    }

    private func makeService(
        diarizer: any SpeakerDiarizer,
        modelStore: any SpeakerDiarizationModelStore,
        mode: TranscriptSpeakerDiarizationMode,
        cache: any TranscriptCache = KeyedMemoryTranscriptCache()
    ) -> LocalAudioTranscriptService {
        LocalAudioTranscriptService(
            transcriber: SingleSpanTranscriber(),
            turnSegmenter: PassthroughTurnSegmenter(),
            turnSegmentationMode: { .raw },
            speakerDiarizationMode: { mode },
            cache: cache,
            audioTrackInspector: SingleTrackInspector(),
            speakerDiarizer: diarizer,
            speakerModelStore: modelStore
        )
    }
}

// MARK: - Test doubles

private struct SingleSpanTranscriber: TimedSpeechTranscriber {
    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws
    -> [TimedTranscriptSpan] {
        [
            try TimedTranscriptSpan(
                id: "speech-0",
                text: "Hello world",
                start: 0,
                end: 1,
                source: request.source
            )
        ]
    }
}

private struct PassthroughTurnSegmenter: TranscriptTurnSegmenter {
    func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            turnSpanIDs: [spans.map(\.id)],
            localeIdentifier: locale.identifier
        )
    }
}

private struct SingleTrackInspector: AudioTrackInspector {
    func audioTrackCount(in audioURL: URL) async throws -> Int {
        1
    }
}

private actor SpySpeakerDiarizer: SpeakerDiarizer {
    private(set) var requests: [SpeakerDiarizationRequest] = []
    private let segments: [SpeakerDiarizationSegment]
    private let embeddings: [String: [Float]]

    init(segments: [SpeakerDiarizationSegment], embeddings: [String: [Float]] = [:]) {
        self.segments = segments
        self.embeddings = embeddings
    }

    func diarize(_ request: SpeakerDiarizationRequest) async throws -> SpeakerDiarizationOutput {
        requests.append(request)
        return SpeakerDiarizationOutput(segments: segments, speakerEmbeddings: embeddings)
    }
}

private struct FailingSpeakerDiarizer: SpeakerDiarizer {
    struct DiarizationFailed: Error {}

    func diarize(_ request: SpeakerDiarizationRequest) async throws -> SpeakerDiarizationOutput {
        throw DiarizationFailed()
    }
}

private actor StubSpeakerModelStore: SpeakerDiarizationModelStore {
    static let revision = "test-model-revision"

    struct PreparationFailed: Error {}

    private var isReady: Bool
    private let prepareFails: Bool
    private(set) var prepareCallCount = 0

    init(initiallyReady: Bool, prepareFails: Bool = false) {
        isReady = initiallyReady
        self.prepareFails = prepareFails
    }

    func modelInfo() -> SpeakerDiarizationModelInfo {
        SpeakerDiarizationModelInfo(
            displayName: "Test Model",
            repository: "test/repo",
            revision: Self.revision,
            expectedDownloadBytes: 1000,
            licenseIdentifier: nil
        )
    }

    func currentState() -> SpeakerDiarizationModelState {
        isReady ? .ready(installedBytes: 1000, modelRevision: Self.revision)
            : .notDownloaded(expectedBytes: 1000)
    }

    func prepareModel() throws -> SpeakerDiarizationModelState {
        prepareCallCount += 1
        if prepareFails {
            throw PreparationFailed()
        }

        isReady = true
        return currentState()
    }

    func removeModel() {
        isReady = false
    }
}

private final class KeyedMemoryTranscriptCache: TranscriptCache, @unchecked Sendable {
    private var storage: [String: TurnSegmentedTranscript] = [:]
    private(set) var savedRequests: [AudioTranscriptRequest] = []

    func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript? {
        storage[key(for: request)]
    }

    func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest) throws {
        savedRequests.append(request)
        storage[key(for: request)] = transcript
    }

    private func key(for request: AudioTranscriptRequest) -> String {
        [
            request.audioURL.path,
            request.locale.identifier,
            request.turnSegmentationMode.rawValue,
            request.speakerDiarizationMode.rawValue,
            request.speakerModelRevision ?? "",
            request.speakerLibraryRevision ?? "",
            request.speakerDiarizationMode == .enabled
                ? request.speakerCountHint.cacheIdentifier : ""
        ].joined(separator: "|")
    }
}
