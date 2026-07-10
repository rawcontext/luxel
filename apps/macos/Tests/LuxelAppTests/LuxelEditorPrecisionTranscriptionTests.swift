import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@Suite("Luxel editor Precision transcription")
@MainActor
struct LuxelEditorPrecisionTranscriptionTests {
    @Test("Precision extraction bypasses Speech authorization entirely")
    func precisionExtractionBypassesSpeechAuthorization() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/precision-audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone)
        )
        let authorizationService = StubSpeechAuthorizationService(
            state: .notDetermined,
            requestedState: .authorized
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService,
            speechRecognitionAuthorizationService: authorizationService,
            transcriptEnginePreference: { .precision }
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        _ = try await helper.waitForTranscript(model)
        #expect(!model.shouldShowSpeechRecognitionPrompt)
        #expect(model.speechRecognitionAuthorizationState == nil)
        #expect(await authorizationService.requests() == 0)
        #expect(await transcriptService.requests().count == 1)
    }

    @Test("transcript configuration changes clear and re-extract an open transcript")
    func transcriptConfigurationChangesInvalidateOpenTranscript() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/changing-engine.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .system)
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService,
            transcriptEnginePreference: { .precision }
        )
        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        _ = try await helper.waitForTranscript(model)

        model.refreshTranscriptionConfiguration()
        _ = try await helper.waitForTranscript(model)
        #expect(await transcriptService.requests().count == 2)
    }
}
