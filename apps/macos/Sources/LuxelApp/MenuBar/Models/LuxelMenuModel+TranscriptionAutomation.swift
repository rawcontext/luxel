import Foundation
import LuxelCore

private enum AutomationTranscriptionError: LocalizedError {
    case missingInput
    case outputExists
    case speechRecognitionDenied
    case precisionModelNotInstalled
    case precisionModelCorrupt
    case precisionLanguageUnsupported(String)
    case precisionInferenceFailed
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingInput:
            "transcription_input_missing: The input media file does not exist."
        case .outputExists:
            "transcription_output_exists: The output file already exists. Use --overwrite to replace it."
        case .speechRecognitionDenied:
            "speech_recognition_denied: Apple Speech permission was not granted."
        case .precisionModelNotInstalled:
            "precision_model_not_installed: Install Precision Transcription in Luxel Settings or switch to Apple Speech."
        case .precisionModelCorrupt:
            "precision_model_corrupt: Repair Precision Transcription in Luxel Settings or switch to Apple Speech."
        case .precisionLanguageUnsupported(let language):
            "precision_language_unsupported: Precision Transcription does not support \(language). Change the language or switch to Apple Speech."
        case .precisionInferenceFailed:
            "precision_inference_failed: Precision Transcription failed. Retry or switch to Apple Speech."
        case .unavailable:
            "transcription_unavailable: Luxel could not produce a transcript."
        }
    }
}

@MainActor
extension LuxelMenuModel {
    func runAutomationTranscription(
        _ options: AutomationTranscriptionOptions
    ) async throws -> AutomationExecutionResult {
        var isDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(
                atPath: options.inputURL.path,
                isDirectory: &isDirectory
            ), !isDirectory.boolValue
        else {
            throw AutomationTranscriptionError.missingInput
        }
        if let outputURL = options.outputURL,
           FileManager.default.fileExists(atPath: outputURL.path),
           !options.overwrite {
            throw AutomationTranscriptionError.outputExists
        }

        if settings.transcriptEnginePreference == .appleSpeech {
            let authorization = await AppleSpeechRecognitionAuthorizationService()
                .requestAuthorization()
            guard authorization == .authorized else {
                throw AutomationTranscriptionError.speechRecognitionDenied
            }
        }

        let locale = Locale(identifier: options.localeIdentifier ?? Locale.current.identifier)
        let mode: TranscriptTurnSegmentationMode = options.semanticTurns ? .semantic : .raw
        let service = LuxelCompositionRoot.localAudioTranscriptService(
            turnSegmentationModeOverride: mode,
            speakerDiarizationModeOverride: options.diarize ? .enabled : .disabled,
            transcriptLocaleOverride: { locale }
        )
        let transcript: TurnSegmentedTranscript
        do {
            guard
                let result = try await service.transcript(
                    for: AudioTranscriptRequest(
                        audioURL: options.inputURL,
                        locale: locale,
                        sourceContext: .unknown,
                        turnSegmentationMode: mode
                    )
                )
            else {
                throw AutomationTranscriptionError.unavailable
            }
            transcript = result
        } catch let error as PrecisionTranscriptionError {
            switch error {
            case .modelNotInstalled:
                throw AutomationTranscriptionError.precisionModelNotInstalled
            case .modelCorrupt:
                throw AutomationTranscriptionError.precisionModelCorrupt
            case .unsupportedLanguage(let language):
                throw AutomationTranscriptionError.precisionLanguageUnsupported(language)
            default:
                throw AutomationTranscriptionError.precisionInferenceFailed
            }
        }

        let data: Data
        let contentType: String
        let fileExtension: String
        if options.json {
            data = try LuxelTranscriptFormatter.data(for: transcript, json: true)
            contentType = "application/json"
            fileExtension = "json"
        } else {
            data = try LuxelTranscriptFormatter.data(for: transcript, json: false)
            contentType = "text/plain; charset=utf-8"
            fileExtension = "txt"
        }

        if let outputURL = options.outputURL {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: outputURL, options: .atomic)
            return .file(outputURL)
        }

        let resultDirectory = FileManager.default.temporaryDirectory
            .appending(path: "Luxel", directoryHint: .isDirectory)
            .appending(path: "Automation", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: resultDirectory,
            withIntermediateDirectories: true
        )
        let resultURL = resultDirectory.appending(
            path: "transcript-\(UUID().uuidString).\(fileExtension)"
        )
        try data.write(to: resultURL, options: .atomic)
        return .resultFile(resultURL, contentType: contentType, removeAfterRead: true)
    }
}
