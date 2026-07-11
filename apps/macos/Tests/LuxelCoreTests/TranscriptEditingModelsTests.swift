import Foundation
import LuxelCore
import Testing

@Suite("Transcript editing")
struct TranscriptEditingModelsTests {
    @Test("indexes sentences inside each turn and maps whole timed spans")
    func indexesSentences() throws {
        let transcript = try sampleTranscript()
        let sentences = try TranscriptSentenceIndex(transcript: transcript).sentences

        #expect(sentences.map(\.text) == ["Hello world.", "How are you?", "Fine."])
        #expect(sentences.map(\.spanIDs) == [["s0", "s1"], ["s2", "s3", "s4"], ["s5"]])
        #expect(sentences[1].sourceRange == (try TimeRange(start: 1.2, end: 2.3)))
        #expect(sentences[2].turnID == "turn-1")
    }

    @Test("manual sentence cut is clipped to trim and preserves originals")
    func plansSentenceCut() throws {
        let transcript = try sampleTranscript()
        let sentence = try TranscriptSentenceIndex(transcript: transcript).sentences[0]
        let plannedCut = try TranscriptSentenceCutPlanner().cut(
            transcript: transcript,
            sentenceID: sentence.id,
            trimRange: TimeRange(start: 0.2, end: 4),
            editPlan: .empty,
            minimumRetainedDuration: 0.1
        )
        let cut = try #require(plannedCut)

        #expect(cut.sourceRange == (try TimeRange(start: 0, end: 1)))
        let inserted = try TimelineEditPlan.empty.inserting(
            cut,
            within: TimeRange(start: 0.2, end: 4),
            minimumRetainedDuration: 0.1
        )
        let updated = try #require(inserted)
        #expect(updated.cuts[0].sourceRange == (try TimeRange(start: 0.2, end: 1)))
        #expect(transcript.spans.count == 6)
    }

    @Test("edited transcript hides fully and partially cut sentences")
    func hidesCutSentences() throws {
        let transcript = try sampleTranscript()
        let index = try TranscriptSentenceIndex(transcript: transcript)
        let plan = try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "partial",
                sourceRange: TimeRange(start: 1.5, end: 1.7),
                kind: .transcriptSentence,
                transcriptSpanIDs: ["s3"]
            )
        ])

        #expect(index.visible(with: plan).map(\.text) == ["Hello world.", "Fine."])
    }

    @Test("planner returns no cut for an already hidden sentence")
    func skipsAlreadyCutSentence() throws {
        let transcript = try sampleTranscript()
        let sentence = try TranscriptSentenceIndex(transcript: transcript).sentences[0]
        let plan = try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "existing",
                sourceRange: sentence.sourceRange,
                kind: .transcriptSentence,
                transcriptSpanIDs: sentence.spanIDs
            )
        ])

        #expect(
            try TranscriptSentenceCutPlanner().cut(
                transcript: transcript,
                sentenceID: sentence.id,
                trimRange: TimeRange(start: 0, end: 4),
                editPlan: plan,
                minimumRetainedDuration: 0.1
            ) == nil
        )
    }

    @Test("planner combines a contiguous sentence group into one cut")
    func plansContiguousSentenceGroup() throws {
        let transcript = try sampleTranscript()
        let sentences = try TranscriptSentenceIndex(transcript: transcript).sentences

        let cut = try TranscriptSentenceCutPlanner().cut(
            transcript: transcript,
            sentenceIDs: Array(sentences[0...1].map(\.id)),
            trimRange: TimeRange(start: 0, end: 4),
            editPlan: .empty,
            minimumRetainedDuration: 0.1
        )

        #expect(cut?.sourceRange == (try TimeRange(start: 0, end: 2.3)))
        #expect(cut?.transcriptSpanIDs == ["s0", "s1", "s2", "s3", "s4"])
    }

    @Test("planner rejects a noncontiguous sentence group")
    func rejectsNoncontiguousSentenceGroup() throws {
        let transcript = try sampleTranscript()
        let sentences = try TranscriptSentenceIndex(transcript: transcript).sentences

        #expect(throws: TimelineEditingError.noncontiguousTranscriptSelection) {
            _ = try TranscriptSentenceCutPlanner().cut(
                transcript: transcript,
                sentenceIDs: [sentences[0].id, sentences[2].id],
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
