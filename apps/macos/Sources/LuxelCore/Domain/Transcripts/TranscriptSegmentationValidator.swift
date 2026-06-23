import Foundation

public struct TranscriptTurnCandidate: Equatable, Sendable {
    public let id: String
    public let spanIDs: [String]
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let source: TranscriptSourceLabel?

    public init(
        id: String,
        spanIDs: [String],
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        source: TranscriptSourceLabel? = nil
    ) {
        self.id = id
        self.spanIDs = spanIDs
        self.start = start
        self.end = end
        self.text = text
        self.source = source
    }
}

public enum TranscriptSegmentationValidator {
    public static func makeTranscript(
        spans: [TimedTranscriptSpan],
        candidates: [TranscriptTurnCandidate],
        localeIdentifier: String
    ) throws -> TurnSegmentedTranscript {
        guard !spans.isEmpty, !candidates.isEmpty else {
            throw TranscriptModelError.invalidTranscript
        }

        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        var expectedSpanIndex = spans.startIndex
        var seenSpanIDs: Set<String> = []
        var turns: [TranscriptTurn] = []

        for (candidateIndex, candidate) in candidates.enumerated() {
            guard !candidate.spanIDs.isEmpty else {
                throw TranscriptModelError.invalidTurn
            }

            var turnSpans: [TimedTranscriptSpan] = []
            for spanID in candidate.spanIDs {
                guard seenSpanIDs.insert(spanID).inserted else {
                    throw TranscriptModelError.duplicateSpan(spanID)
                }
                guard let span = spansByID[spanID] else {
                    throw TranscriptModelError.missingSpan(spanID)
                }
                guard expectedSpanIndex < spans.endIndex,
                      spans[expectedSpanIndex].id == spanID
                else {
                    throw TranscriptModelError.reorderedSpan(spanID)
                }

                turnSpans.append(span)
                expectedSpanIndex = spans.index(after: expectedSpanIndex)
            }

            let trustedText = joinedText(turnSpans)
            guard candidate.text == trustedText else {
                throw TranscriptModelError.changedTurnText(candidate.id)
            }

            let trustedSource = commonSource(for: turnSpans)
            if let candidateSource = candidate.source, candidateSource != trustedSource {
                throw TranscriptModelError.inventedSource(candidate.id)
            }

            let trustedStart = turnSpans[0].start
            let trustedEnd = turnSpans[turnSpans.count - 1].end
            guard isClose(candidate.start, trustedStart),
                  isClose(candidate.end, trustedEnd)
            else {
                throw TranscriptModelError.invalidTurnTiming(candidate.id)
            }

            turns.append(
                try TranscriptTurn(
                    id: candidate.id.isEmpty ? "turn-\(candidateIndex)" : candidate.id,
                    spanIDs: candidate.spanIDs,
                    start: trustedStart,
                    end: trustedEnd,
                    text: trustedText,
                    source: trustedSource
                ))
        }

        guard expectedSpanIndex == spans.endIndex else {
            throw TranscriptModelError.missingSpan(spans[expectedSpanIndex].id)
        }

        return try TurnSegmentedTranscript(
            spans: spans,
            turns: turns,
            localeIdentifier: localeIdentifier
        )
    }

    public static func makeTranscript(
        spans: [TimedTranscriptSpan],
        turnSpanIDs: [[String]],
        localeIdentifier: String
    ) throws -> TurnSegmentedTranscript {
        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        let candidates = try turnSpanIDs.enumerated().map { index, spanIDs in
            guard !spanIDs.isEmpty else {
                throw TranscriptModelError.invalidTurn
            }

            let turnSpans = try spanIDs.map { spanID in
                guard let span = spansByID[spanID] else {
                    throw TranscriptModelError.missingSpan(spanID)
                }
                return span
            }

            return TranscriptTurnCandidate(
                id: "turn-\(index)",
                spanIDs: spanIDs,
                start: turnSpans[0].start,
                end: turnSpans[turnSpans.count - 1].end,
                text: joinedText(turnSpans),
                source: commonSource(for: turnSpans)
            )
        }

        return try makeTranscript(
            spans: spans,
            candidates: candidates,
            localeIdentifier: localeIdentifier
        )
    }

    public static func validate(transcript: TurnSegmentedTranscript) throws {
        try validate(spans: transcript.spans, turns: transcript.turns)
    }

    public static func validate(spans: [TimedTranscriptSpan], turns: [TranscriptTurn]) throws {
        let candidates = turns.map {
            TranscriptTurnCandidate(
                id: $0.id,
                spanIDs: $0.spanIDs,
                start: $0.start,
                end: $0.end,
                text: $0.text,
                source: $0.source
            )
        }
        try validate(spans: spans, candidates: candidates)
    }

    private static func validate(
        spans: [TimedTranscriptSpan],
        candidates: [TranscriptTurnCandidate]
    ) throws {
        guard !spans.isEmpty, !candidates.isEmpty else {
            throw TranscriptModelError.invalidTranscript
        }

        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        var expectedSpanIndex = spans.startIndex
        var seenSpanIDs: Set<String> = []

        for candidate in candidates {
            guard !candidate.spanIDs.isEmpty else {
                throw TranscriptModelError.invalidTurn
            }

            var turnSpans: [TimedTranscriptSpan] = []
            for spanID in candidate.spanIDs {
                guard seenSpanIDs.insert(spanID).inserted else {
                    throw TranscriptModelError.duplicateSpan(spanID)
                }
                guard let span = spansByID[spanID] else {
                    throw TranscriptModelError.missingSpan(spanID)
                }
                guard expectedSpanIndex < spans.endIndex,
                      spans[expectedSpanIndex].id == spanID
                else {
                    throw TranscriptModelError.reorderedSpan(spanID)
                }

                turnSpans.append(span)
                expectedSpanIndex = spans.index(after: expectedSpanIndex)
            }

            guard candidate.text == joinedText(turnSpans) else {
                throw TranscriptModelError.changedTurnText(candidate.id)
            }

            let trustedSource = commonSource(for: turnSpans)
            if let candidateSource = candidate.source, candidateSource != trustedSource {
                throw TranscriptModelError.inventedSource(candidate.id)
            }

            guard isClose(candidate.start, turnSpans[0].start),
                  isClose(candidate.end, turnSpans[turnSpans.count - 1].end)
            else {
                throw TranscriptModelError.invalidTurnTiming(candidate.id)
            }
        }

        guard expectedSpanIndex == spans.endIndex else {
            throw TranscriptModelError.missingSpan(spans[expectedSpanIndex].id)
        }
    }

    private static func joinedText(_ spans: [TimedTranscriptSpan]) -> String {
        spans.map(\.text).joined(separator: " ")
    }

    private static func commonSource(for spans: [TimedTranscriptSpan]) -> TranscriptSourceLabel? {
        guard let firstSource = spans.first?.source,
              spans.allSatisfy({ $0.source == firstSource })
        else {
            return nil
        }

        return firstSource
    }

    private static func isClose(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) <= 0.05
    }
}
