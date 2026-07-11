import Foundation

public protocol AudioTranscriptService: Sendable {
    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript?
    func transcript(
        for request: AudioTranscriptRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> TurnSegmentedTranscript?
    /// Persists a caller-updated transcript (for example after renaming a speaker)
    /// under the same effective cache key the service would use for `request`.
    func storeUpdatedTranscript(
        _ transcript: TurnSegmentedTranscript,
        for request: AudioTranscriptRequest
    ) async throws
}

extension AudioTranscriptService {
    public func transcript(
        for request: AudioTranscriptRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> TurnSegmentedTranscript? {
        let transcript = try await transcript(for: request)
        progress(SpeechTranscriptionProgress(fractionCompleted: 1))
        return transcript
    }

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
    public let speakerCountHint: TranscriptSpeakerCountHint
    public let speakerModelRevision: String?
    public let speakerLibraryRevision: String?
    public let transcriptionProvenance: TranscriptionProvenance

    public init(
        audioURL: URL,
        locale: Locale = .current,
        sourceContext: TranscriptSourceContext = .unknown,
        turnSegmentationMode: TranscriptTurnSegmentationMode = .semantic,
        speakerDiarizationMode: TranscriptSpeakerDiarizationMode = .disabled,
        speakerCountHint: TranscriptSpeakerCountHint = .automatic,
        speakerModelRevision: String? = nil,
        speakerLibraryRevision: String? = nil,
        transcriptionProvenance: TranscriptionProvenance = .appleSpeech
    ) {
        self.audioURL = audioURL
        self.locale = locale
        self.sourceContext = sourceContext
        self.turnSegmentationMode = turnSegmentationMode
        self.speakerDiarizationMode = speakerDiarizationMode
        self.speakerCountHint = speakerCountHint.normalized
        self.speakerModelRevision = speakerModelRevision
        self.speakerLibraryRevision = speakerLibraryRevision
        self.transcriptionProvenance = transcriptionProvenance
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
            speakerCountHint: speakerCountHint,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision,
            transcriptionProvenance: transcriptionProvenance
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
            speakerCountHint: speakerCountHint,
            speakerModelRevision: speakerDiarizationMode == .enabled ? modelRevision : nil,
            speakerLibraryRevision: speakerDiarizationMode == .enabled ? libraryRevision : nil,
            transcriptionProvenance: transcriptionProvenance
        )
    }

    public func replacingSpeakerCountHint(
        _ speakerCountHint: TranscriptSpeakerCountHint
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerCountHint: speakerCountHint,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision,
            transcriptionProvenance: transcriptionProvenance
        )
    }

    public func replacingLocale(_ locale: Locale) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerCountHint: speakerCountHint,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision,
            transcriptionProvenance: transcriptionProvenance
        )
    }

    public func replacingTranscriptionProvenance(
        _ transcriptionProvenance: TranscriptionProvenance
    ) -> AudioTranscriptRequest {
        AudioTranscriptRequest(
            audioURL: audioURL,
            locale: locale,
            sourceContext: sourceContext,
            turnSegmentationMode: turnSegmentationMode,
            speakerDiarizationMode: speakerDiarizationMode,
            speakerCountHint: speakerCountHint,
            speakerModelRevision: speakerModelRevision,
            speakerLibraryRevision: speakerLibraryRevision,
            transcriptionProvenance: transcriptionProvenance
        )
    }
}

public enum TranscriptSpeakerCountHint: Equatable, Hashable, Sendable {
    case automatic
    case exact(Int)
    case range(min: Int, max: Int)

    public var normalized: TranscriptSpeakerCountHint {
        switch self {
        case .automatic:
            return .automatic
        case .exact(let count):
            return .exact(max(1, count))
        case .range(let min, let max):
            let lower = Swift.max(1, Swift.min(min, max))
            let upper = Swift.max(lower, Swift.max(min, max))
            return .range(min: lower, max: upper)
        }
    }

    public var cacheIdentifier: String {
        switch normalized {
        case .automatic:
            return "auto"
        case .exact(let count):
            return "exact-\(count)"
        case .range(let min, let max):
            return "range-\(min)-\(max)"
        }
    }
}

public protocol TimedSpeechTranscriber: Sendable {
    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws -> [TimedTranscriptSpan]
    func transcribe(
        _ request: TimedSpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> [TimedTranscriptSpan]
}

extension TimedSpeechTranscriber {
    public func transcribe(
        _ request: TimedSpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> [TimedTranscriptSpan] {
        let spans = try await transcribe(request)
        progress(SpeechTranscriptionProgress(fractionCompleted: 1))
        return spans
    }
}

public struct TimedSpeechTranscriptionRequest: Equatable, Sendable {
    public let audioURL: URL
    public let locale: Locale
    public let source: TranscriptSourceLabel?
    public let audioTrackIndex: Int?
    public let transcriptionProvenance: TranscriptionProvenance

    public init(
        audioURL: URL,
        locale: Locale,
        source: TranscriptSourceLabel? = nil,
        audioTrackIndex: Int? = nil,
        transcriptionProvenance: TranscriptionProvenance = .appleSpeech
    ) {
        self.audioURL = audioURL
        self.locale = locale
        self.source = source
        self.audioTrackIndex = audioTrackIndex
        self.transcriptionProvenance = transcriptionProvenance
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
