import Foundation
import Testing

@testable import LuxelCore

// MARK: - Speaker-aware segmentation

@Suite("Speaker-aware turn segmentation")
struct SpeakerAwareSegmentationTests {
    @Test("raw segmenter splits turns on speaker changes")
    func rawSegmenterSplitsOnSpeakerChanges() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "One", start: 0, end: 1, speakerID: "a"),
            try TimedTranscriptSpan(id: "span-1", text: "Two", start: 1, end: 2, speakerID: "a"),
            try TimedTranscriptSpan(id: "span-2", text: "Three", start: 2, end: 3, speakerID: "b"),
            try TimedTranscriptSpan(id: "span-3", text: "Four", start: 3, end: 4)
        ]

        let groups = RawTranscriptTurnSegmenter.turnSpanIDs(from: spans)

        #expect(groups == [["span-0", "span-1"], ["span-2"], ["span-3"]])
    }

    @Test("raw segmenter still splits on source changes")
    func rawSegmenterSplitsOnSourceChanges() throws {
        let spans = [
            try TimedTranscriptSpan(
                id: "span-0", text: "One", start: 0, end: 1, source: .system, speakerID: "a"),
            try TimedTranscriptSpan(
                id: "span-1", text: "Two", start: 1, end: 2, source: .microphone, speakerID: "a")
        ]

        let groups = RawTranscriptTurnSegmenter.turnSpanIDs(from: spans)

        #expect(groups == [["span-0"], ["span-1"]])
    }

    @Test("semantic turns that mix speakers are post-split deterministically")
    func semanticTurnsPostSplitOnSpeakerRuns() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "One", start: 0, end: 1, speakerID: "a"),
            try TimedTranscriptSpan(id: "span-1", text: "Two", start: 1, end: 2, speakerID: "b"),
            try TimedTranscriptSpan(id: "span-2", text: "Three", start: 2, end: 3, speakerID: "b")
        ]

        let groups = LocalAudioTranscriptService.splittingTurnsOnSpeakerChanges(
            turnSpanIDs: [["span-0", "span-1", "span-2"]],
            spans: spans
        )

        #expect(groups == [["span-0"], ["span-1", "span-2"]])
    }
}
