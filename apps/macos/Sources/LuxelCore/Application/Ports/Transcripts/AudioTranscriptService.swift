import Foundation

public protocol AudioTranscriptService: Sendable {
    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript?
    /// Persists a caller-updated transcript (for example after renaming a speaker)
    /// under the same effective cache key the service would use for `request`.
    func storeUpdatedTranscript(
        _ transcript: TurnSegmentedTranscript,
        for request: AudioTranscriptRequest
    ) async throws
}

extension AudioTranscriptService {
    public func storeUpdatedTranscript(
        _ transcript: TurnSegmentedTranscript,
        for request: AudioTranscriptRequest
    ) async throws {}
}

public enum TranscriptTurnSegmentationMode: String, Codable, Equatable, Sendable {
    case semantic
    case raw
}

public enum SpeechRecognitionAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

public protocol SpeechRecognitionAuthorizationService: Sendable {
    func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState
    func requestAuthorization() async -> SpeechRecognitionAuthorizationState
}

public struct AudioTranscriptRequest: Equatable, Sendable {
    public let audioURL: URL
    public let locale: Locale
    public let sourceContext: TranscriptSourceContext
    public let turnSegmentationMode: TranscriptTurnSegmentationMode
    public let speakerDiarizationMode: TranscriptSpeakerDiarizationMode
    public let speakerModelRevision: String?
    public let speakerLibraryRevision: String?

    public init(
        audioURL: URL,
        locale: Locale = .current,
        sourceContext: TranscriptSourceContext = .unknown,
        turnSegmentationMode: TranscriptTurnSegmentationMode = .semantic,
        speakerDiarizationMode: TranscriptSpeakerDiarizationMode = .disabled,
        speakerModelRevision: String? = nil,
        speakerLibraryRevision: String? = nil
    ) {
        self.audioURL = audioURL
        self.locale = locale
        self.sourceContext = sourceContext
        self.turnSegmentationMode = turnSegmentationMode
        self.speakerDiarizationMode = speakerDiarizationMode
        self.speakerModelRevision = speakerModelRevision
        self.speakerLibraryRevision = speakerLibraryRevision
    }

    public func replacingTurnSegmentationMode(
        _ turnSegmentationMode: TranscriptTurnSegmentationMode
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision
        )
    }

    public func replacingSpeakerDiarizationMode(
        _ speakerDiarizationMode: TranscriptSpeakerDiarizationMode,
        modelRevision: String? = nil,
        libraryRevision: String? = nil
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerModelRevision: speakerDiarizationMode == .enabled ? modelRevision : nil,
            speakerLibraryRevision: speakerDiarizationMode == .enabled ? libraryRevision : nil
        )
    }

    public func replacingLocale(_ locale: Locale) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision
        )
    }
}

public protocol TimedSpeechTranscriber: Sendable {
    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws -> [TimedTranscriptSpan]
}

public struct TimedSpeechTranscriptionRequest: Equatable, Sendable {
    public let audioURL: URL
    public let locale: Locale
    public let source: TranscriptSourceLabel?
    public let audioTrackIndex: Int?

    public init(
        audioURL: URL,
        locale: Locale,
        source: TranscriptSourceLabel? = nil,
        audioTrackIndex: Int? = nil
    ) {
        self.audioURL = audioURL
        self.locale = locale
        self.source = source
        self.audioTrackIndex = audioTrackIndex
    }
}

public protocol TranscriptTurnSegmenter: Sendable {
    func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript
}

public protocol TranscriptCache: Sendable {
    func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript?
    func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest) throws
}

public struct AudioTrackLayout: Equatable, Sendable {
    public let trackKinds: [AudioTrackKind?]

    public init(trackKinds: [AudioTrackKind?]) {
        self.trackKinds = trackKinds
    }

    public init(audioTrackCount: Int) {
        self.trackKinds = Array(repeating: nil, count: max(0, audioTrackCount))
    }

    public var count: Int {
        trackKinds.count
    }

    public func firstIndex(of kind: AudioTrackKind) -> Int? {
        trackKinds.firstIndex { $0 == kind }
    }
}

public protocol AudioTrackInspector: Sendable {
    func audioTrackCount(in audioURL: URL) async throws -> Int
    func audioTrackLayout(in audioURL: URL) async throws -> AudioTrackLayout
}

extension AudioTrackInspector {
    public func audioTrackLayout(in audioURL: URL) async throws -> AudioTrackLayout {
        try await AudioTrackLayout(audioTrackCount: audioTrackCount(in: audioURL))
    }
}
