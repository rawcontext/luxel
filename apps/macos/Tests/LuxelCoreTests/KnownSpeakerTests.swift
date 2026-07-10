import Foundation
import Testing

@testable import LuxelCore

// MARK: - Matcher

@Suite("Known speaker matcher")
struct KnownSpeakerMatcherTests {
    private let modelIdentifier = "speaker-diarization-coreml@fluidaudio-test"

    private func profile(
        named name: String,
        vector: [Float],
        backend: SpeakerEmbeddingBackend = .fluidAudioWeSpeaker,
        modelIdentifier: String? = nil
    ) throws -> KnownSpeakerProfile {
        try KnownSpeakerProfile(
            displayName: name,
            embeddings: [
                try SpeakerEmbedding(
                    vector: vector,
                    modelIdentifier: modelIdentifier ?? self.modelIdentifier,
                    backend: backend
                )
            ]
        )
    }

    @Test("matches only compatible embedding backends and model identity")
    func matchesOnlyCompatibleBackends() throws {
        let vector: [Float] = [1, 0, 0]
        let incompatibleBackend = try profile(
            named: "Wrong Backend", vector: vector, backend: .fluidAudioCampPlus)
        let incompatibleModel = try profile(
            named: "Wrong Model", vector: vector, modelIdentifier: "other-model")
        let matcher = KnownSpeakerMatcher(modelIdentifier: modelIdentifier)

        let matches = matcher.matches(
            for: ["speaker-0": vector],
            library: KnownSpeakerLibrary(
                profiles: [incompatibleBackend, incompatibleModel],
                revision: "1"
            )
        )

        #expect(matches.isEmpty)
    }

    @Test("requires minimum similarity and second-best margin")
    func requiresMinimumSimilarityAndMargin() throws {
        let matcher = KnownSpeakerMatcher(
            configuration: KnownSpeakerMatcherConfiguration(
                minimumSimilarity: 0.8,
                minimumSecondBestMargin: 0.15
            ),
            modelIdentifier: modelIdentifier
        )
        let target = try profile(named: "Target", vector: [1, 0, 0])
        let nearTwin = try profile(named: "Near Twin", vector: [0.95, 0.3122499, 0])

        // Below the similarity floor: stays anonymous.
        let weak = matcher.matches(
            for: ["speaker-0": [0, 1, 0]],
            library: KnownSpeakerLibrary(profiles: [target], revision: "1")
        )
        #expect(weak.isEmpty)

        // Strong best match but runner-up within the margin: stays anonymous.
        let ambiguous = matcher.matches(
            for: ["speaker-0": [1, 0.05, 0]],
            library: KnownSpeakerLibrary(profiles: [target, nearTwin], revision: "1")
        )
        #expect(ambiguous.isEmpty)

        // Strong and unambiguous: matched.
        let confident = matcher.matches(
            for: ["speaker-0": [1, 0, 0]],
            library: KnownSpeakerLibrary(profiles: [target], revision: "1")
        )
        #expect(confident["speaker-0"]?.displayName == "Target")
    }

    @Test("resolves conflicts globally when two voices claim one profile")
    func resolvesConflictsGlobally() throws {
        let matcher = KnownSpeakerMatcher(
            configuration: KnownSpeakerMatcherConfiguration(
                minimumSimilarity: 0.5,
                minimumSecondBestMargin: 0
            ),
            modelIdentifier: modelIdentifier
        )
        let profile = try profile(named: "Contested", vector: [1, 0, 0])

        let matches = matcher.matches(
            for: [
                "speaker-0": [1, 0, 0],
                "speaker-1": [0.9, 0.4358899, 0]
            ],
            library: KnownSpeakerLibrary(profiles: [profile], revision: "1")
        )

        #expect(matches.count == 1)
        #expect(matches["speaker-0"]?.displayName == "Contested")
        #expect(matches["speaker-1"] == nil)
    }

    @Test("cosine similarity handles identical orthogonal and invalid vectors")
    func cosineSimilarityBehaves() {
        #expect(abs(KnownSpeakerMatcher.cosineSimilarity([1, 0], [1, 0]) - 1) < 0.0001)
        #expect(abs(KnownSpeakerMatcher.cosineSimilarity([1, 0], [0, 1])) < 0.0001)
        #expect(KnownSpeakerMatcher.cosineSimilarity([1, 0], [1, 0, 0]) == -1)
        #expect(KnownSpeakerMatcher.cosineSimilarity([], []) == -1)
        #expect(KnownSpeakerMatcher.cosineSimilarity([0, 0], [1, 0]) == -1)
    }

    @Test("rejects malformed embedding vectors")
    func rejectsMalformedEmbeddings() {
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [],
                modelIdentifier: "model",
                backend: .fluidAudioWeSpeaker
            )
        }
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [1, .nan],
                modelIdentifier: "model",
                backend: .fluidAudioWeSpeaker
            )
        }
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [1, 2],
                modelIdentifier: "",
                backend: .fluidAudioWeSpeaker
            )
        }
    }
}
