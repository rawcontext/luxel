import Foundation
import LuxelCore
import LuxelPresentation

extension LuxelCompositionRoot {
    static func knownSpeakerProfileStore() -> FileKnownSpeakerProfileStore {
        FileKnownSpeakerProfileStore(directory: knownSpeakersDirectory)
    }

    static func speakerDiarizationArtifactsStore()
        -> SpeakerDiarizationArtifactsFileStore {
        SpeakerDiarizationArtifactsFileStore(
            directory: diarizationArtifactsDirectory
        )
    }

    static func speakerVoiceNamingService() -> SpeakerVoiceNamingService {
        SpeakerVoiceNamingService(
            artifactsStore: speakerDiarizationArtifactsStore(),
            profileStore: knownSpeakerProfileStore()
        )
    }

    static func localAudioTranscriptService(
        turnSegmentationModeOverride: TranscriptTurnSegmentationMode? = nil,
        speakerDiarizationModeOverride: TranscriptSpeakerDiarizationMode? = nil,
        transcriptLocaleOverride: (@Sendable () -> Locale?)? = nil
    ) -> LocalAudioTranscriptService {
        let settingsStore = settingsStore()
        return LocalAudioTranscriptService(
            transcriber: AppleSpeechTranscriptExtractor(),
            turnSegmenter: AppleIntelligenceTurnSegmenter(),
            turnSegmentationMode: {
                if let turnSegmentationModeOverride {
                    return turnSegmentationModeOverride
                }
                let settings = (try? settingsStore.load()) ?? defaultSettings
                return settings.transcriptTurnSegmentationEnabled ? .semantic : .raw
            },
            speakerDiarizationMode: {
                if let speakerDiarizationModeOverride {
                    return speakerDiarizationModeOverride
                }
                let settings = (try? settingsStore.load()) ?? defaultSettings
                return settings.transcriptSpeakerDiarizationEnabled ? .enabled : .disabled
            },
            transcriptLocaleOverride: {
                if let transcriptLocaleOverride {
                    return transcriptLocaleOverride()
                }
                let settings = (try? settingsStore.load()) ?? defaultSettings
                return settings.transcriptLanguageIdentifier.map(Locale.init(identifier:))
            },
            transcriptionProvenance: {
                .appleSpeech
            },
            cache: ApplicationSupportTranscriptCache(cacheDirectory: transcriptCacheDirectory),
            audioTrackInspector: AVFoundationAudioTrackInspector(),
            speakerDiarizer: FluidAudioSpeakerDiarizer(
                modelsDirectory: speakerDiarizationModelsDirectory),
            speakerModelStore: speakerDiarizationModelStore,
            knownSpeakerStore: knownSpeakerProfileStore(),
            diarizationArtifactsStore: speakerDiarizationArtifactsStore()
        )
    }

    static var speakerDiarizationModelsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "FluidAudio", directoryHint: .isDirectory)
            .appending(path: "SpeakerDiarization", directoryHint: .isDirectory)
    }

    private static var transcriptCacheDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "Transcripts", directoryHint: .isDirectory)
    }

    private static var knownSpeakersDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "Known Speakers", directoryHint: .isDirectory)
    }

    private static var diarizationArtifactsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "Transcripts", directoryHint: .isDirectory)
            .appending(path: "Diarization", directoryHint: .isDirectory)
    }
}
