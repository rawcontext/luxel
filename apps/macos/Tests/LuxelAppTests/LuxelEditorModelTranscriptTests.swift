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
        #expect(await transcriptService.requests().isEmpty)
    }
}
