import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor transcript performance")
struct LuxelEditorTranscriptPerformanceTests {
    @Test("playback ticks reuse the cached index for a long transcript")
    func playbackTicksReuseLongTranscriptIndex() throws {
        let transcript = try longTranscript(wordCount: 18_000)
        let model = LuxelEditorModelTests().makeModel(
            audioTranscriptService: SpyAudioTranscriptService(transcript: transcript)
        )
        model.source = try SourceMedia.audioOnly(
            fileURL: URL(fileURLWithPath: "/tmp/long-recording.m4a"),
            duration: 5_400
        )
        model.isTranscriptPanelVisible = true
        model.transcript = transcript
        let displayRevision = model.transcriptDisplayRevision
        var activeWordCount = 0

        let elapsed = ContinuousClock().measure {
            for index in stride(from: 0, to: 18_000, by: 10) {
                model.currentPlaybackTime = Double(index) * 0.3 + 0.1
                if model.activeTranscriptSpanID != nil,
                   model.activeTranscriptTurnID != nil {
                    activeWordCount += 1
                }
            }
        }

        #expect(activeWordCount == 1_800)
        #expect(model.transcriptDisplayRevision == displayRevision)
        #expect(elapsed < .seconds(1))
    }

    @Test("transcript card construction does not rebuild the long display plan")
    func transcriptCardConstructionIsConstantTime() throws {
        let transcript = try longTranscript(wordCount: 18_000)
        let words = try TranscriptWordIndex(transcript: transcript).words
        var observedWordCount = 0

        let elapsed = ContinuousClock().measure {
            for _ in 0..<200 {
                let content = TranscriptCardContent(
                    transcript: transcript,
                    words: words,
                    displayRevision: 1,
                    activeTurnID: nil,
                    activeSpanID: nil,
                    spansPerChunk: 32,
                    selectedWordIDs: [],
                    cutCount: 0,
                    editStatusMessage: nil,
                    canDeleteSelectedWord: false,
                    canClose: false,
                    closeTranscript: {},
                    selectWord: { _, _ in },
                    deleteSelectedWord: {}
                )
                observedWordCount = content.words.count
            }
        }

        #expect(observedWordCount == 18_000)
        #expect(elapsed < .seconds(1))
    }

    private func longTranscript(wordCount: Int) throws -> TurnSegmentedTranscript {
        let spans = try (0..<wordCount).map { index in
            let start = Double(index) * 0.3
            return try TimedTranscriptSpan(
                id: "word-\(index)",
                text: "word\(index)",
                start: start,
                end: start + 0.2
            )
        }
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: spans.map(\.id),
                    start: 0,
                    end: spans[spans.count - 1].end,
                    text: spans.map(\.text).joined(separator: " ")
                )
            ],
            localeIdentifier: "en_US"
        )
    }
}
