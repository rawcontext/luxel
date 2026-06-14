import Foundation

public typealias SpeechTranscriptionProgressHandler = @Sendable (SpeechTranscriptionProgress) -> Void

public protocol SpeechTranscriber: Sendable {
    func transcribe(
        _ request: SpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> SpeechTranscriptionResult
}

public struct SpeechTranscriptionRequest: Equatable, Sendable {
    public let audioURL: URL
    public let preferredLanguage: Locale.LanguageCode?
    public let sourceTrack: AudioTrackKind?

    public init(
        audioURL: URL,
        preferredLanguage: Locale.LanguageCode? = nil,
        sourceTrack: AudioTrackKind? = nil
    ) {
        self.audioURL = audioURL
        self.preferredLanguage = preferredLanguage
        self.sourceTrack = sourceTrack
    }
}

public struct SpeechTranscriptionProgress: Equatable, Sendable {
    public let fractionCompleted: Double

    public init(fractionCompleted: Double) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
    }
}

public struct SpeechTranscriptionResult: Equatable, Sendable {
    public let words: [RecognizedWord]
    public let language: Locale.LanguageCode

    public init(
        words: [RecognizedWord],
        language: Locale.LanguageCode
    ) {
        self.words = words
        self.language = language
    }
}
