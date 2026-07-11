import Foundation

public struct SelectedEngineTimedSpeechTranscriber: TimedSpeechTranscriber {
    private let appleSpeech: any TimedSpeechTranscriber
    private let precision: any TimedSpeechTranscriber

    public init(
        appleSpeech: any TimedSpeechTranscriber,
        precision: any TimedSpeechTranscriber
    ) {
        self.appleSpeech = appleSpeech
        self.precision = precision
    }

    public func transcribe(
        _ request: TimedSpeechTranscriptionRequest
    ) async throws -> [TimedTranscriptSpan] {
        try await transcribe(request, progress: { _ in })
    }

    public func transcribe(
        _ request: TimedSpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> [TimedTranscriptSpan] {
        switch request.transcriptionProvenance.engine {
        case .appleSpeech:
            try await appleSpeech.transcribe(request, progress: progress)
        case .parakeetTDTv3:
            try await precision.transcribe(request, progress: progress)
        }
    }
}

public struct SelectedEngineCaptionSpeechTranscriber: SpeechTranscriber {
    private let appleSpeech: (any SpeechTranscriber)?
    private let precision: any SpeechTranscriber
    private let provenance: @Sendable () async throws -> TranscriptionProvenance

    public init(
        appleSpeech: (any SpeechTranscriber)? = nil,
        precision: any SpeechTranscriber,
        provenance: @escaping @Sendable () async throws -> TranscriptionProvenance
    ) {
        self.appleSpeech = appleSpeech
        self.precision = precision
        self.provenance = provenance
    }

    public func transcribe(
        _ request: SpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> SpeechTranscriptionResult {
        switch try await provenance().engine {
        case .appleSpeech:
            guard let appleSpeech else {
                throw PrecisionTranscriptionError.appleCaptionTranscriberUnavailable
            }
            return try await appleSpeech.transcribe(request, progress: progress)
        case .parakeetTDTv3:
            return try await precision.transcribe(request, progress: progress)
        }
    }
}
