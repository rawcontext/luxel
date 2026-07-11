import Foundation
import NaturalLanguage

public struct TranscriptEditableSentence: Equatable, Identifiable, Sendable {
    public let id: String
    public let turnID: String
    public let spanIDs: [String]
    public let text: String
    public let sourceRange: TimeRange

    public init(
        id: String,
        turnID: String,
        spanIDs: [String],
        text: String,
        sourceRange: TimeRange
    ) {
        self.id = id
        self.turnID = turnID
        self.spanIDs = spanIDs
        self.text = text
        self.sourceRange = sourceRange
    }
}

public struct TranscriptSentenceIndex: Equatable, Sendable {
    public let sentences: [TranscriptEditableSentence]

    public init(transcript: TurnSegmentedTranscript) throws {
        let spansByID = Dictionary(uniqueKeysWithValues: transcript.spans.map { ($0.id, $0) })
        sentences = try transcript.turns.flatMap { turn in
            let spans = turn.spanIDs.compactMap { spansByID[$0] }
            return try Self.sentences(turn: turn, spans: spans)
        }
    }

    public func visible(with editPlan: TimelineEditPlan) -> [TranscriptEditableSentence] {
        sentences.filter { !editPlan.removes($0.sourceRange) }
    }

    private static func sentences(
        turn: TranscriptTurn,
        spans: [TimedTranscriptSpan]
    ) throws -> [TranscriptEditableSentence] {
        let searchable = SearchableTranscriptSpans(spans: spans)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = searchable.text
        let tokenRanges = tokenizer.tokens(for: searchable.text.startIndex..<searchable.text.endIndex)
        let ranges = tokenRanges.isEmpty
            ? [searchable.text.startIndex..<searchable.text.endIndex]
            : tokenRanges

        return try ranges.enumerated().compactMap { index, range in
            let includedSpans = searchable.spans(overlapping: range)
            guard let first = includedSpans.first, let last = includedSpans.last else {
                return nil
            }

            return TranscriptEditableSentence(
                id: "\(turn.id)-sentence-\(index)",
                turnID: turn.id,
                spanIDs: includedSpans.map(\.id),
                text: String(searchable.text[range]).trimmingCharacters(in: .whitespacesAndNewlines),
                sourceRange: try TimeRange(start: first.start, end: last.end)
            )
        }
    }
}

public struct TranscriptSentenceCutPlanner: Equatable, Sendable {
    public init() {}

    public func cut(
        transcript: TurnSegmentedTranscript,
        sentenceID: TranscriptEditableSentence.ID,
        trimRange: TimeRange,
        editPlan: TimelineEditPlan,
        minimumRetainedDuration: TimeInterval
    ) throws -> TimelineCut? {
        try cut(
            transcript: transcript,
            sentenceIDs: [sentenceID],
            trimRange: trimRange,
            editPlan: editPlan,
            minimumRetainedDuration: minimumRetainedDuration
        )
    }

    public func cut(
        transcript: TurnSegmentedTranscript,
        sentenceIDs: [TranscriptEditableSentence.ID],
        trimRange: TimeRange,
        editPlan: TimelineEditPlan,
        minimumRetainedDuration: TimeInterval
    ) throws -> TimelineCut? {
        let sentences = try TranscriptSentenceIndex(transcript: transcript).sentences.filter {
            !editPlan.removes($0.sourceRange)
        }
        let selectedIDs = Set(sentenceIDs)
        let selectedIndexes = sentences.indices.filter { selectedIDs.contains(sentences[$0].id) }
        guard let firstIndex = selectedIndexes.first, let lastIndex = selectedIndexes.last else {
            return nil
        }
        guard selectedIndexes == Array(firstIndex...lastIndex) else {
            throw TimelineEditingError.noncontiguousTranscriptSelection
        }
        let selectedSentences = Array(sentences[firstIndex...lastIndex])
        guard let first = selectedSentences.first,
              let last = selectedSentences.last
        else {
            return nil
        }

        let cut = try TimelineCut(
            id: "transcript-\(first.id)-\(last.id)",
            sourceRange: TimeRange(
                start: first.sourceRange.start,
                end: last.sourceRange.end
            ),
            kind: .transcriptSentence,
            transcriptSpanIDs: selectedSentences.flatMap(\.spanIDs)
        )
        guard try editPlan.inserting(
            cut,
            within: trimRange,
            minimumRetainedDuration: minimumRetainedDuration
        ) != nil else {
            return nil
        }
        return cut
    }
}

private struct SearchableTranscriptSpans {
    struct SpanRange {
        let span: TimedTranscriptSpan
        let range: Range<String.Index>
    }

    let text: String
    let spanRanges: [SpanRange]

    init(spans: [TimedTranscriptSpan]) {
        var text = ""
        var ranges: [SpanRange] = []
        for span in spans {
            if !text.isEmpty {
                text.append(" ")
            }
            let start = text.endIndex
            text.append(span.text)
            ranges.append(SpanRange(span: span, range: start..<text.endIndex))
        }
        self.text = text
        spanRanges = ranges
    }

    func spans(overlapping range: Range<String.Index>) -> [TimedTranscriptSpan] {
        spanRanges.compactMap {
            $0.range.lowerBound < range.upperBound && range.lowerBound < $0.range.upperBound
                ? $0.span
                : nil
        }
    }
}
