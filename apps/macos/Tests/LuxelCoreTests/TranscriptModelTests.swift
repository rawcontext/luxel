import Foundation
import LuxelCore
import Testing

@Suite("Transcript models")
struct TranscriptModelTests {
    @Test("validator accepts exact ordered source attributed turns")
    func validatorAcceptsExactOrderedSourceAttributedTurns() throws {
        let spans = try sampleSpans(source: .microphone)
        let transcript = try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            candidates: [
                TranscriptTurnCandidate(
                    id: "turn-0",
                    spanIDs: ["span-0", "span-1"],
                    start: 0,
                    end: 0.9,
                    text: "Hello there",
                    source: .microphone
                )
            ],
            localeIdentifier: "en_US"
        )

        #expect(transcript.turns.first?.source == .microphone)
        #expect(transcript.turns.first?.text == "Hello there")
    }

    @Test("validator rejects model output that changes text")
    func validatorRejectsChangedText() throws {
        let spans = try sampleSpans(source: nil)

        #expect(throws: TranscriptModelError.changedTurnText("turn-0")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [
                    TranscriptTurnCandidate(
                        id: "turn-0",
                        spanIDs: ["span-0", "span-1"],
                        start: 0,
                        end: 0.9,
                        text: "Hello there.",
                        source: nil
                    )
                ],
                localeIdentifier: "en_US"
            )
        }
    }

    @Test("validator reconstructs exact turns from generated span id groups")
    func validatorReconstructsTurnsFromSpanIDGroups() throws {
        let spans = try sampleSpans(source: .microphone)
        let transcript = try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            turnSpanIDs: [["span-0", "span-1"]],
            localeIdentifier: "en_US"
        )

        #expect(
            transcript.turns == [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: ["span-0", "span-1"],
                    start: 0,
                    end: 0.9,
                    text: "Hello there",
                    source: .microphone
                )
            ])
    }

    @Test("validator rejects duplicate reordered missing and invented source spans")
    func validatorRejectsInvalidCoverageAndSources() throws {
        let spans = try sampleSpans(source: .system)

        #expect(throws: TranscriptModelError.duplicateSpan("span-0")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [
                    TranscriptTurnCandidate(
                        id: "turn-0",
                        spanIDs: ["span-0", "span-0"],
                        start: 0,
                        end: 0.4,
                        text: "Hello Hello",
                        source: .system
                    )
                ],
                localeIdentifier: "en_US"
            )
        }

        #expect(throws: TranscriptModelError.reorderedSpan("span-1")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [
                    TranscriptTurnCandidate(
                        id: "turn-0",
                        spanIDs: ["span-1", "span-0"],
                        start: 0.5,
                        end: 0.4,
                        text: "there Hello",
                        source: .system
                    )
                ],
                localeIdentifier: "en_US"
            )
        }

        #expect(throws: TranscriptModelError.missingSpan("span-1")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [
                    TranscriptTurnCandidate(
                        id: "turn-0",
                        spanIDs: ["span-0"],
                        start: 0,
                        end: 0.4,
                        text: "Hello",
                        source: .system
                    )
                ],
                localeIdentifier: "en_US"
            )
        }

        #expect(throws: TranscriptModelError.inventedSource("turn-0")) {
            _ = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: [
                    TranscriptTurnCandidate(
                        id: "turn-0",
                        spanIDs: ["span-0", "span-1"],
                        start: 0,
                        end: 0.9,
                        text: "Hello there",
                        source: .microphone
                    )
                ],
                localeIdentifier: "en_US"
            )
        }
    }

    @Test("source context maps recording audio modes without inferring unknown media")
    func sourceContextMapsRecordingAudioModes() {
        #expect(
            TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil))
                .extractionPlans(audioTrackCount: 1)
                == [TranscriptExtractionPlan(source: .microphone)]
        )
        #expect(
            TranscriptSourceContext(recordingAudioMode: .system)
                .extractionPlans(audioTrackCount: 1)
                == [TranscriptExtractionPlan(source: .system)]
        )
        #expect(
            TranscriptSourceContext(recordingAudioMode: .systemAndMicrophone(deviceID: nil))
                .extractionPlans(audioTrackCount: 2)
                == [
                    TranscriptExtractionPlan(source: .system, audioTrackIndex: 0),
                    TranscriptExtractionPlan(source: .microphone, audioTrackIndex: 1)
                ]
        )
        #expect(
            TranscriptSourceContext(recordingAudioMode: .systemAndMicrophone(deviceID: nil))
                .extractionPlans(audioTrackCount: 1)
                == [TranscriptExtractionPlan(source: nil)]
        )
        #expect(
            TranscriptSourceContext.unknown.extractionPlans(audioTrackCount: 1)
                == [TranscriptExtractionPlan(source: nil)]
        )
    }

    private func sampleSpans(source: TranscriptSourceLabel?) throws -> [TimedTranscriptSpan] {
        [
            try TimedTranscriptSpan(
                id: "span-0",
                text: "Hello",
                start: 0,
                end: 0.4,
                confidence: 0.9,
                source: source
            ),
            try TimedTranscriptSpan(
                id: "span-1",
                text: "there",
                start: 0.5,
                end: 0.9,
                confidence: 0.92,
                source: source
            )
        ]
    }
}
