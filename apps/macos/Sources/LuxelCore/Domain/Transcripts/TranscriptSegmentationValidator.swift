import Foundation

public struct TranscriptTurnCandidate: Equatable, Sendable {
    public let source: TranscriptSourceLabel?
    public let speakerID: String?
    public let id: String
    public let spanIDs: [String]
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(
        id: String,
        spanIDs: [String],
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        source: TranscriptSourceLabel? = nil,
        speakerID: String? = nil
    ) {
        self.id = id
        self.spanIDs = spanIDs
        self.start = start
        self.end = end
        self.text = text
        self.source = source
        self.speakerID = speakerID
    }
}

public enum TranscriptSegmentationValidator {
    public static func makeTranscript(
        spans: [TimedTranscriptSpan],
        candidates: [TranscriptTurnCandidate],
        localeIdentifier: String,
        speakers: [TranscriptSpeakerLabel] = []
    ) throws -> TurnSegmentedTranscript {
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: validatedTurns(spans: spans, candidates: candidates),
            localeIdentifier: localeIdentifier,
            speakers: speakers
        )
    }

    public static func makeTranscript(
        spans: [TimedTranscriptSpan],
        turnSpanIDs: [[String]],
        localeIdentifier: String,
        speakers: [TranscriptSpeakerLabel] = []
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
                source: commonSource(for: turnSpans),
                speakerID: try commonSpeaker(for: turnSpans, turnID: "turn-\(index)")
            )
        }

        return try makeTranscript(
            spans: spans,
            candidates: candidates,
            localeIdentifier: localeIdentifier,
            speakers: speakers
        )
    }

    public static func validate(transcript: TurnSegmentedTranscript) throws {
        try validate(
            spans: transcript.spans,
            turns: transcript.turns,
            speakers: transcript.speakers
        )
    }

    public static func validate(
        spans: [TimedTranscriptSpan],
        turns: [TranscriptTurn],
        speakers: [TranscriptSpeakerLabel] = []
    ) throws {
        let candidates = turns.map {
            TranscriptTurnCandidate(
                id: $0.id,
                spanIDs: $0.spanIDs,
                start: $0.start,
                end: $0.end,
                text: $0.text,
                source: $0.source,
                speakerID: $0.speakerID
            )
        }
        _ = try validatedTurns(spans: spans, candidates: candidates)
        try validateSpeakerReferences(spans: spans, turns: turns, speakers: speakers)
    }

    private static func validateSpeakerReferences(
        spans: [TimedTranscriptSpan],
        turns: [TranscriptTurn],
        speakers: [TranscriptSpeakerLabel]
    ) throws {
        var declaredSpeakerIDs: Set<String> = []
        for speaker in speakers {
            guard declaredSpeakerIDs.insert(speaker.id).inserted else {
                throw TranscriptModelError.duplicateSpeakerLabel(speaker.id)
            }
        }

        let referencedSpeakerIDs = Set(spans.compactMap(\.speakerID))
            .union(turns.compactMap(\.speakerID))
        if let unknown = referencedSpeakerIDs.subtracting(declaredSpeakerIDs).sorted().first {
            throw TranscriptModelError.unknownSpeaker(unknown)
        }
    }

    private static func validatedTurns(
        spans: [TimedTranscriptSpan],
        candidates: [TranscriptTurnCandidate]
    ) throws -> [TranscriptTurn] {
        guard !spans.isEmpty, !candidates.isEmpty else {
            throw TranscriptModelError.invalidTranscript
        }

        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        var expectedSpanIndex = spans.startIndex
        var seenSpanIDs: Set<String> = []
        var turns: [TranscriptTurn] = []

        for (candidateIndex, candidate) in candidates.enumerated() {
            let turnSpans = try orderedTurnSpans(
                for: candidate,
                spans: spans,
                spansByID: spansByID,
                expectedSpanIndex: &expectedSpanIndex,
                seenSpanIDs: &seenSpanIDs
            )

            let trustedText = joinedText(turnSpans)
            guard candidate.text == trustedText else {
                throw TranscriptModelError.changedTurnText(candidate.id)
            }

            let attribution = try trustedAttribution(for: candidate, turnSpans: turnSpans)
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
                    source: attribution.source,
                    speakerID: attribution.speakerID
                ))
        }

        guard expectedSpanIndex == spans.endIndex else {
            throw TranscriptModelError.missingSpan(spans[expectedSpanIndex].id)
        }
        return turns
    }

    private static func orderedTurnSpans(
        for candidate: TranscriptTurnCandidate,
        spans: [TimedTranscriptSpan],
        spansByID: [String: TimedTranscriptSpan],
        expectedSpanIndex: inout Int,
        seenSpanIDs: inout Set<String>
    ) throws -> [TimedTranscriptSpan] {
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

        return turnSpans
    }

    private static func joinedText(_ spans: [TimedTranscriptSpan]) -> String {
        spans.map(\.text).joined(separator: " ")
    }

    private static func trustedAttribution(
        for candidate: TranscriptTurnCandidate,
        turnSpans: [TimedTranscriptSpan]
    ) throws -> (source: TranscriptSourceLabel?, speakerID: String?) {
        let trustedSource = commonSource(for: turnSpans)
        if let candidateSource = candidate.source, candidateSource != trustedSource {
            throw TranscriptModelError.inventedSource(candidate.id)
        }

        let trustedSpeaker = try commonSpeaker(for: turnSpans, turnID: candidate.id)
        if let candidateSpeaker = candidate.speakerID, candidateSpeaker != trustedSpeaker {
            throw TranscriptModelError.inventedSpeaker(candidate.id)
        }

        return (trustedSource, trustedSpeaker)
    }

    private static func commonSource(for spans: [TimedTranscriptSpan]) -> TranscriptSourceLabel? {
        guard let firstSource = spans.first?.source,
            spans.allSatisfy({ $0.source == firstSource })
        else {
            return nil
        }

        return firstSource
    }

    private static func commonSpeaker(
        for spans: [TimedTranscriptSpan],
        turnID: String
    ) throws -> String? {
        let distinctSpeakerIDs = Set(spans.compactMap(\.speakerID))
        guard distinctSpeakerIDs.count <= 1 else {
            throw TranscriptModelError.mixedTurnSpeakers(turnID)
        }
        guard let speakerID = distinctSpeakerIDs.first,
            spans.allSatisfy({ $0.speakerID == speakerID })
        else {
            return nil
        }

        return speakerID
    }

    private static func isClose(_ lhs: TimeInterval, _ rhs: TimeInterval) -> Bool {
        abs(lhs - rhs) <= 0.05
    }
}
