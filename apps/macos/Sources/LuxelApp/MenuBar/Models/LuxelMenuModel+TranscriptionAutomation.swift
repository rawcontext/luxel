import Foundation
import LuxelCore

private enum AutomationTranscriptionError: LocalizedError {
    case missingInput
    case outputExists
    case speechRecognitionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingInput:
            "transcription_input_missing: The input media file does not exist."
        case .outputExists:
            "transcription_output_exists: The output file already exists. Use --overwrite to replace it."
        case .speechRecognitionDenied:
            "speech_recognition_denied: Apple Speech permission was not granted."
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
        try validateAutomationTranscriptionOptions(options)
        try await authorizeAutomationTranscription()
        let locale = Locale(identifier: options.localeIdentifier ?? Locale.current.identifier)
        let mode: TranscriptTurnSegmentationMode = options.semanticTurns ? .semantic : .raw
        let transcript = try await automationTranscript(
            options: options,
            locale: locale,
            mode: mode
        )
        let output = try automationTranscriptOutput(transcript, json: options.json)
        return try writeAutomationTranscriptOutput(output, to: options.outputURL)
    }

    private func validateAutomationTranscriptionOptions(
        _ options: AutomationTranscriptionOptions
    ) throws {
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
    }

    private func authorizeAutomationTranscription() async throws {
        let authorization = await AppleSpeechAuthorizationService()
            .requestAuthorization()
        guard authorization == .authorized else {
            throw AutomationTranscriptionError.speechRecognitionDenied
        }
    }

    private func automationTranscript(
        options: AutomationTranscriptionOptions,
        locale: Locale,
        mode: TranscriptTurnSegmentationMode
    ) async throws -> TurnSegmentedTranscript {
        let service = LuxelCompositionRoot.localAudioTranscriptService(
            turnSegmentationModeOverride: mode,
            speakerDiarizationModeOverride: options.diarize ? .enabled : .disabled,
            transcriptLocaleOverride: { locale }
        )
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
        return result
    }

    private func automationTranscriptOutput(
        _ transcript: TurnSegmentedTranscript,
        json: Bool
    ) throws -> AutomationTranscriptOutput {
        if json {
            return AutomationTranscriptOutput(
                data: try LuxelTranscriptFormatter.data(for: transcript, json: true),
                contentType: "application/json",
                fileExtension: "json"
            )
        }
        return AutomationTranscriptOutput(
            data: try LuxelTranscriptFormatter.data(for: transcript, json: false),
            contentType: "text/plain; charset=utf-8",
            fileExtension: "txt"
        )
    }

    private func writeAutomationTranscriptOutput(
        _ output: AutomationTranscriptOutput,
        to outputURL: URL?
    ) throws -> AutomationExecutionResult {
        if let outputURL {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try output.data.write(to: outputURL, options: .atomic)
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
            path: "transcript-\(UUID().uuidString).\(output.fileExtension)"
        )
        try output.data.write(to: resultURL, options: .atomic)
        return .resultFile(resultURL, contentType: output.contentType, removeAfterRead: true)
    }
}

private struct AutomationTranscriptOutput {
    let data: Data
    let contentType: String
    let fileExtension: String
}
