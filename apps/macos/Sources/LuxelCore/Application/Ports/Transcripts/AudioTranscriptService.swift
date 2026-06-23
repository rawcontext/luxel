import Foundation

public protocol AudioTranscriptService: Sendable {
    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript?
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

    public init(
        audioURL: URL,
        locale: Locale = .current,
        sourceContext: TranscriptSourceContext = .unknown,
        turnSegmentationMode: TranscriptTurnSegmentationMode = .semantic
    ) {
        self.audioURL = audioURL
        self.locale = locale
        self.sourceContext = sourceContext
        self.turnSegmentationMode = turnSegmentationMode
    }

    public func replacingTurnSegmentationMode(
        _ turnSegmentationMode: TranscriptTurnSegmentationMode
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode
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

public protocol AudioTrackInspector: Sendable {
    func audioTrackCount(in audioURL: URL) async throws -> Int
}
