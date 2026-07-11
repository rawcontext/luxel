import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@Suite("Transcript copy text")
struct TranscriptCopyTextBuilderTests {
    @Test("no-cut copy uses original turn text exactly")
    func noCutCopyPreservesOriginalText() throws {
        let transcript = try sampleTranscript()

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: [],
            hasCuts: false
        )

        #expect(text == "Wait... what?")
    }

    @Test("cut copy uses only visible edited words")
    func cutCopyUsesVisibleWords() throws {
        let transcript = try sampleTranscript()
        let visible = [
            TranscriptEditableWord(
                id: "first",
                turnID: "turn",
                text: "Wait...",
                sourceRange: try TimeRange(start: 0, end: 0.5)
            )
        ]

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: visible,
            hasCuts: true
        )

        #expect(text == "Wait...")
    }

    private func sampleTranscript() throws -> TurnSegmentedTranscript {
        let spans = try [
            TimedTranscriptSpan(id: "first", text: "Wait...", start: 0, end: 0.5),
            TimedTranscriptSpan(id: "second", text: "what?", start: 0.6, end: 1)
        ]
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: spans.map(\.id),
                    start: 0,
                    end: 1,
                    text: "Wait... what?"
                )
            ],
            localeIdentifier: "en_US"
        )
    }
}
