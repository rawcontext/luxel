import Foundation

public enum TranscriptSpeakerDiarizationMode: String, Codable, Equatable, Sendable {
    case disabled
    case enabled
}

public struct SpeakerDiarizationRequest: Equatable, Sendable {
    public let audioURL: URL
    public let audioTrackIndex: Int?
    public let modelRevision: String?
    public let speakerCountHint: TranscriptSpeakerCountHint

    public init(
        audioURL: URL,
        audioTrackIndex: Int? = nil,
        modelRevision: String? = nil,
        speakerCountHint: TranscriptSpeakerCountHint = .automatic
    ) {
        self.audioURL = audioURL
        self.audioTrackIndex = audioTrackIndex
        self.modelRevision = modelRevision
        self.speakerCountHint = speakerCountHint.normalized
    }
}

public struct SpeakerDiarizationSegment: Codable, Equatable, Sendable {
    public let speakerID: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(speakerID: String, start: TimeInterval, end: TimeInterval) {
        self.speakerID = speakerID
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        max(0, end - start)
    }
}

public struct SpeakerDiarizationOutput: Equatable, Sendable {
    public let segments: [SpeakerDiarizationSegment]
    public let speakerEmbeddings: [String: [Float]]

    public init(
        segments: [SpeakerDiarizationSegment],
        speakerEmbeddings: [String: [Float]] = [:]
    ) {
        self.segments = segments
        self.speakerEmbeddings = speakerEmbeddings
    }
}

public protocol SpeakerDiarizer: Sendable {
    func diarize(_ request: SpeakerDiarizationRequest) async throws -> SpeakerDiarizationOutput
}

/// Per-recording diarization byproducts kept outside the transcript cache so the
/// editor can offer example clips, speaking-time stats, and enrollment embeddings
/// without re-running diarization.
public struct SpeakerDiarizationArtifacts: Codable, Equatable, Sendable {
    public struct Track: Codable, Equatable, Sendable {
        public let source: TranscriptSourceLabel?
        public let audioTrackIndex: Int?
        public let segments: [SpeakerDiarizationSegment]

        public init(
            source: TranscriptSourceLabel?,
            audioTrackIndex: Int? = nil,
            segments: [SpeakerDiarizationSegment]
        ) {
            self.source = source
            self.audioTrackIndex = audioTrackIndex
            self.segments = segments
        }
    }

    public let modelRevision: String?
    public let tracks: [Track]
    public let speakerEmbeddings: [String: [Float]]

    public init(
        modelRevision: String?,
        tracks: [Track],
        speakerEmbeddings: [String: [Float]]
    ) {
        self.modelRevision = modelRevision
        self.tracks = tracks
        self.speakerEmbeddings = speakerEmbeddings
    }

    public func segments(for speakerID: String) -> [SpeakerDiarizationSegment] {
        tracks.flatMap(\.segments).filter { $0.speakerID == speakerID }
    }
}

public protocol SpeakerDiarizationArtifactsStore: Sendable {
    func load(audioURL: URL) throws -> SpeakerDiarizationArtifacts?
    func save(_ artifacts: SpeakerDiarizationArtifacts, audioURL: URL) throws
}

public enum SpeakerDiarizationModelState: Equatable, Sendable {
    case notDownloaded(expectedBytes: Int64?)
    case preparing(expectedBytes: Int64?)
    case ready(installedBytes: Int64, modelRevision: String?)
    case failed(message: String, expectedBytes: Int64?)

    public var isReady: Bool {
        if case .ready = self {
            return true
        }

        return false
    }

    public var isPreparing: Bool {
        if case .preparing = self {
            return true
        }

        return false
    }
}

public struct SpeakerDiarizationModelInfo: Equatable, Sendable {
    public let displayName: String
    public let repository: String
    public let revision: String?
    public let expectedDownloadBytes: Int64?
    public let licenseIdentifier: String?

    public init(
        displayName: String,
        repository: String,
        revision: String?,
        expectedDownloadBytes: Int64?,
        licenseIdentifier: String?
    ) {
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.expectedDownloadBytes = expectedDownloadBytes
        self.licenseIdentifier = licenseIdentifier
    }
}

public protocol SpeakerDiarizationModelStore: Sendable {
    func modelInfo() async -> SpeakerDiarizationModelInfo
    func currentState() async -> SpeakerDiarizationModelState
    func prepareModel() async throws -> SpeakerDiarizationModelState
    func cancelPreparation() async
    func removeModel() async throws
}

extension SpeakerDiarizationModelStore {
    public func cancelPreparation() async {}
}

public enum SpeakerModelCatalog {
    /// Quality-first ordering: the offline VBx diarization pipeline is FluidAudio's
    /// best documented offline-quality path; size is disclosed, never optimized for.
    public static let speakerDiarization = SpeakerDiarizationModelInfo(
        displayName: "Speaker Diarization (Pyannote/WeSpeaker VBx)",
        repository: "FluidInference/speaker-diarization-coreml",
        revision: "1ed7a662fdc7109e36d822db793ee6eebdaf8594",
        expectedDownloadBytes: 21_776_918,
        licenseIdentifier: "cc-by-4.0"
    )
}
