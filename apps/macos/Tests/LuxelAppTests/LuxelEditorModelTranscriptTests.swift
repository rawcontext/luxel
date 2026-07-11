import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor transcript model")
struct LuxelEditorModelTranscriptTests {
    @Test("opening audio-only source extracts and exposes validated transcript")
    func openingAudioOnlySourceExtractsTranscript() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcript = try helper.sampleTranscript(source: .microphone)
        let transcriptService = SpyAudioTranscriptService(transcript: transcript)
        let sourceContext = TranscriptSourceContext(
            recordingAudioMode: .microphone(deviceID: "mic-1")
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            transcriptSourceContext: sourceContext
        )

        let visibleTranscript = try await helper.waitForTranscript(model)
        #expect(visibleTranscript.turns.first?.source == .microphone)
        #expect(visibleTranscript.turns.first?.text == "Hello world")

        let requests = await transcriptService.requests()
        #expect(
            requests == [
                AudioTranscriptRequest(
                    audioURL: sourceURL,
                    locale: .current,
                    sourceContext: sourceContext
                )
            ])

        model.handlePlaybackTime(0.7)
        #expect(model.activeTranscriptTurnID == "turn-0")
        #expect(model.activeTranscriptSpanID == "span-1")

        model.seekToTranscriptTurn(visibleTranscript.turns[0])
        #expect(model.currentPlaybackTime == 0)

        model.seekToTranscriptSpan(visibleTranscript.spans[1])
        #expect(model.currentPlaybackTime == 0.5)
    }

    @Test("applying an exact speaker count re-runs transcript extraction")
    func applyingExactSpeakerCountRerunsTranscriptExtraction() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone)
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        _ = try await helper.waitForTranscript(model)

        model.setSpeakerCountMode(.exact)
        model.setExactSpeakerCount(5)
        #expect(model.canApplySpeakerCountHint)
        model.applySpeakerCountHint()
        _ = try await helper.waitForTranscript(model)

        let requests = await transcriptService.requests()
        #expect(requests.map(\.speakerCountHint) == [.automatic, .exact(5)])
        #expect(model.appliedSpeakerCountHint == .exact(5))
        #expect(!model.canApplySpeakerCountHint)
    }

    @Test("opening audio-only source infers transcript source from metadata")
    func openingAudioOnlySourceInfersTranscriptSourceFromMetadata() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(
            fileURL: sourceURL,
            duration: 12,
            audioTracks: [.microphone]
        )
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone)
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        let visibleTranscript = try await helper.waitForTranscript(model)
        #expect(visibleTranscript.turns.first?.source == .microphone)
        #expect(
            await transcriptService.requests() == [
                AudioTranscriptRequest(
                    audioURL: sourceURL,
                    locale: .current,
                    sourceContext: TranscriptSourceContext(
                        recordingAudioMode: .microphone(deviceID: nil)
                    )
                )
            ]
        )
    }

}

extension LuxelEditorModelTranscriptTests {
    @Test("transcript progress appears while local extraction is active")
    func transcriptProgressAppearsWhileExtractionIsActive() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 92)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone),
            delay: .milliseconds(150)
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            transcriptSourceContext: TranscriptSourceContext(
                recordingAudioMode: .microphone(deviceID: "mic-1"))
        )

        try await waitForTranscriptProgress(true, model: model)
        #expect(model.visibleTranscript == nil)

        _ = try await helper.waitForTranscript(model)
        #expect(!model.shouldShowTranscriptProgress)
        #expect(!model.isTranscriptExtractionActive)
    }

    @Test("transcript progress hides after extraction failure")
    func transcriptProgressHidesAfterExtractionFailure() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 92)
        let transcriptService = SpyAudioTranscriptService(
            error: TranscriptModelError.invalidTranscript,
            delay: .milliseconds(100)
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        try await waitForTranscriptProgress(true, model: model)
        try await waitForTranscriptProgress(false, model: model)

        #expect(model.visibleTranscript == nil)
        #expect(!model.isTranscriptExtractionActive)
    }

    @Test("opening video source does not request transcript")
    func openingVideoSourceDoesNotRequestTranscript() async throws {
        let helper = LuxelEditorModelTests()
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: nil))
        let model = helper.makeModel(audioTranscriptService: transcriptService)

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        try await Task.sleep(for: .milliseconds(20))

        #expect(model.visibleTranscript == nil)
        #expect(!model.isTranscriptPanelVisible)
        #expect(model.canShowVideoTranscriptToggle)
        #expect(await transcriptService.requests().isEmpty)
    }

    @Test("opening video transcript panel extracts and exposes transcript")
    func openingVideoTranscriptPanelExtractsTranscript() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/video.mp4")
        let transcript = try helper.sampleTranscript(source: .system)
        let transcriptService = SpyAudioTranscriptService(transcript: transcript)
        let model = helper.makeModel(audioTranscriptService: transcriptService)

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(model.visibleTranscript == nil)
        #expect(await transcriptService.requests().isEmpty)

        model.showTranscriptPanel()

        let visibleTranscript = try await helper.waitForTranscript(model)
        #expect(visibleTranscript.turns.first?.text == "Hello world")
        #expect(model.isTranscriptPanelVisible)
        #expect(
            await transcriptService.requests() == [
                AudioTranscriptRequest(
                    audioURL: sourceURL,
                    locale: .current,
                    sourceContext: TranscriptSourceContext(recordingAudioMode: .system)
                )
            ])

        model.hideTranscriptPanel()
        #expect(model.visibleTranscript == nil)
        model.showTranscriptPanel()
        #expect(model.visibleTranscript?.turns.first?.text == "Hello world")
        #expect(await transcriptService.requests().count == 1)
    }

    @Test("video without audio does not expose transcript controls")
    func videoWithoutAudioDoesNotExposeTranscriptControls() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/silent-video.mp4")
        let source = try SourceMedia(
            fileURL: sourceURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: false
        )
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: nil))
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(!model.canShowVideoTranscriptToggle)
        model.showTranscriptPanel()
        try await Task.sleep(for: .milliseconds(20))
        #expect(!model.isTranscriptPanelVisible)
        #expect(await transcriptService.requests().isEmpty)
    }

    @Test("speech prompt appears until the user enables recognition")
    func speechPromptAppearsUntilUserEnablesRecognition() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone))
        let authorizationService = StubSpeechAuthorizationService(
            state: .notDetermined,
            requestedState: .authorized
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService,
            speechRecognitionAuthorizationService: authorizationService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp"),
            transcriptSourceContext: TranscriptSourceContext(
                recordingAudioMode: .microphone(deviceID: "mic-1"))
        )

        try await waitForSpeechRecognitionPrompt(model)
        #expect(await transcriptService.requests().isEmpty)

        model.enableSpeechRecognition()

        let visibleTranscript = try await helper.waitForTranscript(model)
        #expect(visibleTranscript.turns.first?.source == .microphone)
        #expect(!model.shouldShowSpeechRecognitionPrompt)
        #expect(await authorizationService.requests() == 1)
        #expect(await transcriptService.requests().count == 1)
    }

    @Test("speech prompt remains visible after recognition is denied")
    func speechPromptRemainsVisibleAfterRecognitionIsDenied() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let transcriptService = SpyAudioTranscriptService(
            transcript: try helper.sampleTranscript(source: .microphone))
        let authorizationService = StubSpeechAuthorizationService(
            state: .notDetermined,
            requestedState: .denied
        )
        let model = helper.makeModel(
            metadataReader: StubMetadataReader(source: source),
            audioTranscriptService: transcriptService,
            speechRecognitionAuthorizationService: authorizationService
        )

        await model.open(
            fileURL: sourceURL,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        try await waitForSpeechRecognitionPrompt(model)
        model.enableSpeechRecognition()
        try await waitForSpeechRecognitionState(.denied, model: model)

        #expect(model.speechRecognitionAuthorizationState == .denied)
        #expect(model.shouldShowSpeechRecognitionPrompt)
        #expect(model.visibleTranscript == nil)
        #expect(await authorizationService.requests() == 1)
        #expect(await transcriptService.requests().isEmpty)
    }

    private func waitForSpeechRecognitionPrompt(_ model: LuxelEditorModel) async throws {
        for _ in 0..<100 {
            if model.shouldShowSpeechRecognitionPrompt {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.shouldShowSpeechRecognitionPrompt)
    }

    private func waitForTranscriptProgress(_ expected: Bool, model: LuxelEditorModel) async throws {
        for _ in 0..<100 {
            if model.shouldShowTranscriptProgress == expected {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.shouldShowTranscriptProgress == expected)
    }

    private func waitForSpeechRecognitionState(
        _ state: SpeechRecognitionAuthorizationState,
        model: LuxelEditorModel
    ) async throws {
        for _ in 0..<100 {
            if model.speechRecognitionAuthorizationState == state {
                return
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.speechRecognitionAuthorizationState == state)
    }
}
