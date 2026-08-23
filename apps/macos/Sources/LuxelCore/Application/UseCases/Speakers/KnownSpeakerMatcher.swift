import Foundation

public struct KnownSpeakerMatch: Equatable, Sendable {
    public let knownSpeakerID: UUID
    public let displayName: String
    public let similarity: Double
    public let margin: Double

    public init(knownSpeakerID: UUID, displayName: String, similarity: Double, margin: Double) {
        self.knownSpeakerID = knownSpeakerID
        self.displayName = displayName
        self.similarity = similarity
        self.margin = margin
    }
}

public struct KnownSpeakerMatcherConfiguration: Equatable, Sendable {
    /// Minimum cosine similarity a candidate must reach before a name is applied.
    public let minimumSimilarity: Double
    /// Required lead over the runner-up profile so ambiguous voices stay anonymous.
    public let minimumSecondBestMargin: Double

    public init(minimumSimilarity: Double = 0.62, minimumSecondBestMargin: Double = 0.08) {
        self.minimumSimilarity = minimumSimilarity
        self.minimumSecondBestMargin = minimumSecondBestMargin
    }

    public static let `default` = KnownSpeakerMatcherConfiguration()
}

public struct KnownSpeakerMatcher: Sendable {
    private let configuration: KnownSpeakerMatcherConfiguration
    private let backend: SpeakerEmbeddingBackend
    private let modelIdentifier: String

    public init(
        configuration: KnownSpeakerMatcherConfiguration = .default,
        backend: SpeakerEmbeddingBackend = .fluidAudioWeSpeaker,
        modelIdentifier: String
    ) {
        self.configuration = configuration
        self.backend = backend
        self.modelIdentifier = modelIdentifier
    }

    private struct ScoredProfile {
        let profile: KnownSpeakerProfile
        let similarity: Double
    }

    private struct CandidatePairing {
        let speakerID: String
        let profile: KnownSpeakerProfile
        let similarity: Double
    }

    /// Resolves detected speaker embeddings against the known-speaker library.
    ///
    /// Assignment is global: every candidate pairing is scored first and applied
    /// best-first so one profile can never be claimed by two detected speakers.
    public func matches(
        for speakerEmbeddings: [String: [Float]],
        library: KnownSpeakerLibrary
    ) -> [String: KnownSpeakerMatch] {
        let candidatesBySpeaker = speakerEmbeddings.mapValues { embedding in
            scoredProfiles(for: embedding, library: library)
        }

        var matches: [String: KnownSpeakerMatch] = [:]
        var claimedProfiles: Set<UUID> = []
        for pairing in confidentPairings(from: candidatesBySpeaker) {
            guard claimedProfiles.insert(pairing.profile.id).inserted else {
                continue
            }

            let secondBest =
                candidatesBySpeaker[pairing.speakerID]?
                .first { $0.profile.id != pairing.profile.id }?
                .similarity ?? -1
            matches[pairing.speakerID] = KnownSpeakerMatch(
                knownSpeakerID: pairing.profile.id,
                displayName: pairing.profile.displayName,
                similarity: pairing.similarity,
                margin: pairing.similarity - secondBest
            )
        }

        return matches
    }

    private func scoredProfiles(
        for embedding: [Float],
        library: KnownSpeakerLibrary
    ) -> [ScoredProfile] {
        library.profiles.compactMap { profile -> ScoredProfile? in
            let compatible = profile.embeddings.filter {
                $0.backend == backend && $0.modelIdentifier == modelIdentifier
                    && $0.vector.count == embedding.count
            }
            guard
                let best =
                    compatible
                    .map({ Self.cosineSimilarity($0.vector, embedding) })
                    .max()
            else {
                return nil
            }

            return ScoredProfile(profile: profile, similarity: best)
        }
        .sorted { $0.similarity > $1.similarity }
    }

    private func confidentPairings(
        from candidatesBySpeaker: [String: [ScoredProfile]]
    ) -> [CandidatePairing] {
        candidatesBySpeaker.compactMap { speakerID, scored -> CandidatePairing? in
            guard let best = scored.first, best.similarity >= configuration.minimumSimilarity
            else {
                return nil
            }

            let secondBest = scored.dropFirst().first?.similarity ?? -1
            guard best.similarity - secondBest >= configuration.minimumSecondBestMargin else {
                return nil
            }

            return CandidatePairing(
                speakerID: speakerID,
                profile: best.profile,
                similarity: best.similarity
            )
        }
        .sorted {
            if $0.similarity == $1.similarity {
                return $0.speakerID < $1.speakerID
            }

            return $0.similarity > $1.similarity
        }
    }

    public static func cosineSimilarity(_ lhs: [Float], _ rhs: [Float]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return -1
        }

        var dot = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsMagnitude += left * left
            rhsMagnitude += right * right
        }

        let denominator = (lhsMagnitude * rhsMagnitude).squareRoot()
        guard denominator > 0 else {
            return -1
        }

        return dot / denominator
    }
}
