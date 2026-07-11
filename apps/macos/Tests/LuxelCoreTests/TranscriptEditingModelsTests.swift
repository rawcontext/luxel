import Foundation
import LuxelCore
import Testing

@Suite("Transcript editing")
struct TranscriptEditingModelsTests {
    @Test("indexes each timed transcript span as an editable word")
    func indexesWords() throws {
        let words = try TranscriptWordIndex(transcript: sampleTranscript()).words

        #expect(words.map(\.text) == ["Hello", "world.", "How", "are", "you?", "Fine."])
        #expect(words.map(\.id) == ["s0", "s1", "s2", "s3", "s4", "s5"])
        #expect(words[3].sourceRange == (try TimeRange(start: 1.5, end: 1.7)))
        #expect(words[5].turnID == "turn-1")
    }

    @Test("manual word cut is clipped to trim and preserves originals")
    func plansWordCut() throws {
        let transcript = try sampleTranscript()
        let word = try TranscriptWordIndex(transcript: transcript).words[0]
        let plannedCut = try TranscriptWordCutPlanner().cut(
            transcript: transcript,
            wordID: word.id,
            trimRange: TimeRange(start: 0.2, end: 4),
            editPlan: .empty,
            minimumRetainedDuration: 0.1
        )
        let cut = try #require(plannedCut)

        #expect(cut.sourceRange == (try TimeRange(start: 0, end: 0.4)))
        #expect(cut.transcriptSpanIDs == ["s0"])
        let inserted = try TimelineEditPlan.empty.inserting(
            cut,
            within: TimeRange(start: 0.2, end: 4),
            minimumRetainedDuration: 0.1
        )
        let updated = try #require(inserted)
        #expect(updated.cuts[0].sourceRange == (try TimeRange(start: 0.2, end: 0.4)))
        #expect(transcript.spans.count == 6)
    }

    @Test("edited transcript hides only the cut word")
    func hidesCutWord() throws {
        let transcript = try sampleTranscript()
        let index = try TranscriptWordIndex(transcript: transcript)
        let plan = try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "word",
                sourceRange: TimeRange(start: 1.5, end: 1.7),
                kind: .transcriptSentence,
                transcriptSpanIDs: ["s3"]
            )
        ])

        #expect(index.visible(with: plan).map(\.text) == ["Hello", "world.", "How", "you?", "Fine."])
    }

    @Test("planner returns no cut for an already hidden word")
    func skipsAlreadyCutWord() throws {
        let transcript = try sampleTranscript()
        let word = try TranscriptWordIndex(transcript: transcript).words[0]
        let plan = try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "existing",
                sourceRange: word.sourceRange,
                kind: .transcriptSentence,
                transcriptSpanIDs: [word.id]
            )
        ])

        #expect(
            try TranscriptWordCutPlanner().cut(
                transcript: transcript,
                wordID: word.id,
                trimRange: TimeRange(start: 0, end: 4),
                editPlan: plan,
                minimumRetainedDuration: 0.1
            ) == nil
        )
    }

    @Test("planner combines a contiguous word group into one cut")
    func plansContiguousWordGroup() throws {
        let transcript = try sampleTranscript()
        let words = try TranscriptWordIndex(transcript: transcript).words

        let cut = try TranscriptWordCutPlanner().cut(
            transcript: transcript,
            wordIDs: Array(words[1...3].map(\.id)),
            trimRange: TimeRange(start: 0, end: 4),
            editPlan: .empty,
            minimumRetainedDuration: 0.1
        )

        #expect(cut?.sourceRange == (try TimeRange(start: 0.5, end: 1.7)))
        #expect(cut?.transcriptSpanIDs == ["s1", "s2", "s3"])
    }

    @Test("planner rejects a noncontiguous word group")
    func rejectsNoncontiguousWordGroup() throws {
        let transcript = try sampleTranscript()
        let words = try TranscriptWordIndex(transcript: transcript).words

        #expect(throws: TimelineEditingError.noncontiguousTranscriptSelection) {
            _ = try TranscriptWordCutPlanner().cut(
                transcript: transcript,
                wordIDs: [words[0].id, words[2].id],
                trimRange: TimeRange(start: 0, end: 4),
                editPlan: .empty,
                minimumRetainedDuration: 0.1
            )
        }
    }

    private func sampleTranscript() throws -> TurnSegmentedTranscript {
        let spans = try [
            span("s0", "Hello", 0, 0.4),
            span("s1", "world.", 0.5, 1),
            span("s2", "How", 1.2, 1.4),
            span("s3", "are", 1.5, 1.7),
            span("s4", "you?", 1.8, 2.3),
            span("s5", "Fine.", 2.5, 3)
        ]
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                TranscriptTurn(
                    id: "turn-0",
                    spanIDs: Array(spans[0...4].map(\.id)),
                    start: 0,
                    end: 2.3,
                    text: "Hello world. How are you?"
                ),
                TranscriptTurn(
                    id: "turn-1",
                    spanIDs: ["s5"],
                    start: 2.5,
                    end: 3,
                    text: "Fine."
                )
            ],
            localeIdentifier: "en_US"
        )
    }

    private func span(
        _ id: String,
        _ text: String,
        _ start: TimeInterval,
        _ end: TimeInterval
    ) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(id: id, text: text, start: start, end: end)
    }
}
