import Foundation

public struct TranscribeRecordingRequest: Equatable, Sendable {
    public let audioURL: URL
    public let preferredLanguage: Locale.LanguageCode?
    public let sourceTrack: AudioTrackKind?
    public let recordingBundle: RecordingBundle?

    public init(
        audioURL: URL,
        preferredLanguage: Locale.LanguageCode? = nil,
        sourceTrack: AudioTrackKind? = nil,
        recordingBundle: RecordingBundle? = nil
    ) {
        self.audioURL = audioURL
        self.preferredLanguage = preferredLanguage
        self.sourceTrack = sourceTrack
        self.recordingBundle = recordingBundle
    }
}

public struct TranscribedRecording: Equatable, Sendable {
    public let track: CaptionTrack
    public let updatedBundle: RecordingBundle?

    public init(track: CaptionTrack, updatedBundle: RecordingBundle? = nil) {
        self.track = track
        self.updatedBundle = updatedBundle
    }
}

public struct TranscribeRecordingService: Sendable {
    private let transcriber: any SpeechTranscriber
    private let cueBuilder: CaptionCueBuilder
    private let sidecarPersistence: CaptionSidecarPersistenceService?

    public init(
        transcriber: any SpeechTranscriber,
        cueBuilder: CaptionCueBuilder = CaptionCueBuilder(),
        sidecarPersistence: CaptionSidecarPersistenceService? = nil
    ) {
        self.transcriber = transcriber
        self.cueBuilder = cueBuilder
        self.sidecarPersistence = sidecarPersistence
    }

    public func transcribe(
        _ request: TranscribeRecordingRequest,
        progress: @escaping SpeechTranscriptionProgressHandler = { _ in }
    ) async throws -> TranscribedRecording {
        let transcription = try await transcriber.transcribe(
            SpeechTranscriptionRequest(
                audioURL: request.audioURL,
                preferredLanguage: request.preferredLanguage,
                sourceTrack: request.sourceTrack
            ),
            progress: {
                progress(
                    SpeechTranscriptionProgress(
                        fractionCompleted: $0.fractionCompleted * 0.95
                    )
                )
            }
        )
        let cues = try cueBuilder.buildCues(from: transcription.words)
        let track = try CaptionTrack(
            cues: cues,
            language: transcription.language,
            sourceTrack: request.sourceTrack,
            transcriptionProvenance: transcription.provenance
        )
        let updatedBundle = try request.recordingBundle.map { bundle in
            try sidecarPersistence?.save(track, in: bundle) ?? bundle
        }
        progress(SpeechTranscriptionProgress(fractionCompleted: 1))

        return TranscribedRecording(track: track, updatedBundle: updatedBundle)
    }
}
