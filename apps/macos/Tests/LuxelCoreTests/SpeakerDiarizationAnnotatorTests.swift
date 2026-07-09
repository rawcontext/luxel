import Foundation
import Testing

@testable import LuxelCore

// MARK: - Annotator

@Suite("Speaker diarization annotator")
struct SpeakerDiarizationAnnotatorTests {
    @Test("assigns speakers by maximum overlap and builds first-seen labels")
    func assignsSpeakersByMaximumOverlap() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "Hello", start: 0, end: 2),
            try TimedTranscriptSpan(id: "span-1", text: "there", start: 2, end: 4),
            try TimedTranscriptSpan(id: "span-2", text: "friend", start: 4, end: 6)
        ]
        let tracks = [
            SpeakerDiarizationTrackSegments(
                source: nil,
                segments: [
                    SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 2.2),
                    SpeakerDiarizationSegment(speakerID: "speaker-1", start: 2.2, end: 6)
                ])
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: tracks
        )

        #expect(annotated.spans.map(\.speakerID) == ["speaker-0", "speaker-1", "speaker-1"])
        #expect(annotated.speakers.map(\.id) == ["speaker-0", "speaker-1"])
        #expect(annotated.speakers.map(\.displayName) == ["Speaker 1", "Speaker 2"])
        #expect(annotated.speakers.allSatisfy { $0.knownSpeakerID == nil })
    }

    @Test("leaves low-overlap spans unlabeled")
    func leavesLowOverlapSpansUnlabeled() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "Barely", start: 0, end: 10)
        ]
        let tracks = [
            SpeakerDiarizationTrackSegments(
                source: nil,
                segments: [
                    SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 3)
                ])
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: tracks
        )

        #expect(annotated.spans.map(\.speakerID) == [nil])
        #expect(annotated.speakers.isEmpty)
    }

    @Test("preserves text timing source and confidence")
    func preservesSpanContent() throws {
        let span = try TimedTranscriptSpan(
            id: "span-0",
            text: "Untouched",
            start: 1,
            end: 3,
            confidence: 0.75,
            source: .microphone
        )
        let tracks = [
            SpeakerDiarizationTrackSegments(
                source: nil,
                segments: [SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 4)]
            )
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: [span],
            tracks: tracks
        )

        let annotatedSpan = try #require(annotated.spans.first)
        #expect(annotatedSpan.text == span.text)
        #expect(annotatedSpan.start == span.start)
        #expect(annotatedSpan.end == span.end)
        #expect(annotatedSpan.confidence == span.confidence)
        #expect(annotatedSpan.source == span.source)
        #expect(annotatedSpan.speakerID == "speaker-0")
    }

    @Test("handles empty diarization output without inventing labels")
    func handlesEmptyDiarization() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "Quiet", start: 0, end: 1)
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: [SpeakerDiarizationTrackSegments(source: nil, segments: [])]
        )

        #expect(annotated.spans == spans)
        #expect(annotated.speakers.isEmpty)
    }

    @Test("source-scoped tracks only label spans from the same source")
    func sourceScopedTracksRespectSourceBoundaries() throws {
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "Mic", start: 0, end: 2, source: .microphone),
            try TimedTranscriptSpan(id: "span-1", text: "Sys", start: 0, end: 2, source: .system)
        ]
        let tracks = [
            SpeakerDiarizationTrackSegments(
                source: .microphone,
                segments: [
                    SpeakerDiarizationSegment(speakerID: "microphone:speaker-0", start: 0, end: 2)
                ])
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: tracks
        )

        #expect(annotated.spans.map(\.speakerID) == ["microphone:speaker-0", nil])
    }

    @Test("known speaker matches replace anonymous display names")
    func knownSpeakerMatchesReplaceDisplayNames() throws {
        let profileID = UUID()
        let spans = [
            try TimedTranscriptSpan(id: "span-0", text: "Hi", start: 0, end: 2)
        ]
        let tracks = [
            SpeakerDiarizationTrackSegments(
                source: nil,
                segments: [SpeakerDiarizationSegment(speakerID: "speaker-0", start: 0, end: 2)]
            )
        ]

        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: tracks,
            knownSpeakerMatches: [
                "speaker-0": KnownSpeakerMatch(
                    knownSpeakerID: profileID,
                    displayName: "Sarah Chen",
                    similarity: 0.9,
                    margin: 0.5
                )
            ]
        )

        #expect(annotated.speakers.map(\.displayName) == ["Sarah Chen"])
        #expect(annotated.speakers.first?.knownSpeakerID == profileID)
    }
}

// MARK: - Transcript speaker model validation

@Suite("Transcript speaker models")
struct TranscriptSpeakerModelTests {
    private func makeSpans(speakerIDs: [String?]) throws -> [TimedTranscriptSpan] {
        try speakerIDs.enumerated().map { index, speakerID in
            try TimedTranscriptSpan(
                id: "span-\(index)",
                text: "Word\(index)",
                start: TimeInterval(index),
                end: TimeInterval(index) + 1,
                speakerID: speakerID
            )
        }
    }

    @Test("speaker IDs must resolve against declared transcript speakers")
    func speakerIDsMustResolve() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0"])
        let turn = try TranscriptTurn(
            id: "turn-0",
            spanIDs: ["span-0"],
            start: 0,
            end: 1,
            text: "Word0",
            speakerID: "speaker-0"
        )

        #expect(throws: TranscriptModelError.unknownSpeaker("speaker-0")) {
            _ = try TurnSegmentedTranscript(
                spans: spans,
                turns: [turn],
                localeIdentifier: "en_US",
                speakers: []
            )
        }

        let valid = try TurnSegmentedTranscript(
            spans: spans,
            turns: [turn],
            localeIdentifier: "en_US",
            speakers: [try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1")]
        )
        #expect(valid.speaker(for: "speaker-0")?.displayName == "Speaker 1")
    }

    @Test("turns cannot mix distinct speaker IDs")
    func turnsCannotMixSpeakers() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0", "speaker-1"])

        #expect(throws: TranscriptModelError.mixedTurnSpeakers("turn-0")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                turnSpanIDs: [["span-0", "span-1"]],
                localeIdentifier: "en_US",
                speakers: [
                    try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1"),
                    try TranscriptSpeakerLabel(id: "speaker-1", displayName: "Speaker 2")
                ]
            )
        }
    }

    @Test("candidates cannot invent speakers their spans do not carry")
    func candidatesCannotInventSpeakers() throws {
        let spans = try makeSpans(speakerIDs: [nil])
        let candidate = TranscriptTurnCandidate(
            id: "turn-0",
            spanIDs: ["span-0"],
            start: 0,
            end: 1,
            text: "Word0",
            speakerID: "speaker-0"
        )

        #expect(throws: TranscriptModelError.inventedSpeaker("turn-0")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [candidate],
                localeIdentifier: "en_US",
                speakers: [try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1")]
            )
        }
    }

    @Test("deterministic segmentation preserves common speaker labels on turns")
    func segmentationPreservesCommonSpeaker() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0", "speaker-0", nil])

        let transcript = try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            turnSpanIDs: [["span-0", "span-1"], ["span-2"]],
            localeIdentifier: "en_US",
            speakers: [try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1")]
        )

        #expect(transcript.turns.map(\.speakerID) == ["speaker-0", nil])
    }

    @Test("old transcript JSON without speaker fields decodes as non-diarized")
    func oldJSONDecodesAsNonDiarized() throws {
        let json = """
        {
          "localeIdentifier": "en_US",
          "spans": [
            { "id": "span-0", "text": "Legacy", "start": 0, "end": 1 }
          ],
          "turns": [
            { "id": "turn-0", "spanIDs": ["span-0"], "start": 0, "end": 1, "text": "Legacy" }
          ]
        }
        """

        let transcript = try JSONDecoder().decode(
            TurnSegmentedTranscript.self, from: Data(json.utf8))

        #expect(transcript.speakers.isEmpty)
        #expect(transcript.spans.first?.speakerID == nil)
        #expect(transcript.turns.first?.speakerID == nil)
    }

    @Test("duplicate speaker labels are rejected")
    func duplicateSpeakerLabelsRejected() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0"])
        let turn = try TranscriptTurn(
            id: "turn-0",
            spanIDs: ["span-0"],
            start: 0,
            end: 1,
            text: "Word0",
            speakerID: "speaker-0"
        )

        #expect(throws: TranscriptModelError.duplicateSpeakerLabel("speaker-0")) {
            _ = try TurnSegmentedTranscript(
                spans: spans,
                turns: [turn],
                localeIdentifier: "en_US",
                speakers: [
                    try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1"),
                    try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Twin")
                ]
            )
        }
    }

    @Test("replacing a speaker label renames without touching structure")
    func replacingSpeakerLabelRenames() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0"])
        let turn = try TranscriptTurn(
            id: "turn-0",
            spanIDs: ["span-0"],
            start: 0,
            end: 1,
            text: "Word0",
            speakerID: "speaker-0"
        )
        let profileID = UUID()
        let transcript = try TurnSegmentedTranscript(
            spans: spans,
            turns: [turn],
            localeIdentifier: "en_US",
            speakers: [try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1")]
        )

        let renamed = try transcript.replacingSpeakerLabel(
            TranscriptSpeakerLabel(
                id: "speaker-0",
                displayName: "Sarah Chen",
                knownSpeakerID: profileID
            ))

        #expect(renamed.speaker(for: "speaker-0")?.displayName == "Sarah Chen")
        #expect(renamed.speaker(for: "speaker-0")?.knownSpeakerID == profileID)
        #expect(renamed.spans == transcript.spans)
        #expect(renamed.turns == transcript.turns)

        #expect(throws: TranscriptModelError.unknownSpeaker("missing")) {
            _ = try transcript.replacingSpeakerLabel(
                TranscriptSpeakerLabel(id: "missing", displayName: "Nobody"))
        }
    }

    @Test("merging a speaker rewrites references and removes the duplicate label")
    func mergingSpeakerRewritesReferences() throws {
        let spans = try makeSpans(speakerIDs: ["speaker-0", "speaker-1"])
        let turns = [
            try TranscriptTurn(
                id: "turn-0",
                spanIDs: ["span-0"],
                start: 0,
                end: 1,
                text: "Word0",
                speakerID: "speaker-0"
            ),
            try TranscriptTurn(
                id: "turn-1",
                spanIDs: ["span-1"],
                start: 1,
                end: 2,
                text: "Word1",
                speakerID: "speaker-1"
            )
        ]
        let targetProfileID = UUID()
        let transcript = try TurnSegmentedTranscript(
            spans: spans,
            turns: turns,
            localeIdentifier: "en_US",
            speakers: [
                try TranscriptSpeakerLabel(
                    id: "speaker-0",
                    displayName: "Jordan Smith",
                    knownSpeakerID: targetProfileID
                ),
                try TranscriptSpeakerLabel(id: "speaker-1", displayName: "Speaker 2")
            ]
        )

        let merged = try transcript.mergingSpeaker(id: "speaker-1", into: "speaker-0")

        #expect(merged.speakers.map(\.id) == ["speaker-0"])
        #expect(merged.speakers.first?.knownSpeakerID == targetProfileID)
        #expect(merged.spans.map(\.speakerID) == ["speaker-0", "speaker-0"])
        #expect(merged.turns.map(\.speakerID) == ["speaker-0", "speaker-0"])
    }
}

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
