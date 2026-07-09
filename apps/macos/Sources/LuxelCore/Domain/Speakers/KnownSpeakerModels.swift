import Foundation

public enum SpeakerEmbeddingBackend: String, Codable, Equatable, Sendable {
    case fluidAudioWeSpeaker
    case fluidAudioCampPlus
}

public struct SpeakerEmbedding: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let vector: [Float]
    public let modelIdentifier: String
    public let modelRevision: String?
    public let backend: SpeakerEmbeddingBackend
    public let sourceClipID: UUID?

    public init(
        id: UUID = UUID(),
        vector: [Float],
        modelIdentifier: String,
        modelRevision: String? = nil,
        backend: SpeakerEmbeddingBackend,
        sourceClipID: UUID? = nil
    ) throws {
        guard !vector.isEmpty, vector.allSatisfy(\.isFinite), !modelIdentifier.isEmpty else {
            throw KnownSpeakerError.invalidEmbedding
        }

        self.id = id
        self.vector = vector
        self.modelIdentifier = modelIdentifier
        self.modelRevision = modelRevision
        self.backend = backend
        self.sourceClipID = sourceClipID
    }
}

public struct KnownSpeakerExampleClip: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let audioURL: URL
    public let duration: TimeInterval
    public let sourceRecordingURL: URL?

    public init(
        id: UUID = UUID(),
        audioURL: URL,
        duration: TimeInterval,
        sourceRecordingURL: URL? = nil
    ) throws {
        guard duration.isFinite, duration > 0 else {
            throw KnownSpeakerError.invalidExampleClip
        }

        self.id = id
        self.audioURL = audioURL
        self.duration = duration
        self.sourceRecordingURL = sourceRecordingURL
    }
}

public struct KnownSpeakerProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var embeddings: [SpeakerEmbedding]
    public var exampleClips: [KnownSpeakerExampleClip]
    public var matchedRecordingCount: Int
    public var lastMatchedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        embeddings: [SpeakerEmbedding],
        exampleClips: [KnownSpeakerExampleClip] = [],
        matchedRecordingCount: Int = 0,
        lastMatchedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDisplayName.isEmpty else {
            throw KnownSpeakerError.invalidDisplayName
        }
        guard !embeddings.isEmpty else {
            throw KnownSpeakerError.invalidEmbedding
        }

        self.id = id
        self.displayName = normalizedDisplayName
        self.embeddings = embeddings
        self.exampleClips = exampleClips
        self.matchedRecordingCount = matchedRecordingCount
        self.lastMatchedAt = lastMatchedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum KnownSpeakerError: Error, Equatable, Sendable {
    case invalidDisplayName
    case invalidEmbedding
    case invalidExampleClip
    case profileNotFound(UUID)
}
