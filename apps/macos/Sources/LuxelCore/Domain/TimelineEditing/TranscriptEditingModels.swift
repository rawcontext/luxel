import Foundation

public struct TranscriptEditableWord: Equatable, Identifiable, Sendable {
    public let id: String
    public let turnID: String
    public let text: String
    public let sourceRange: TimeRange

    public init(
        id: String,
        turnID: String,
        text: String,
        sourceRange: TimeRange
    ) {
        self.id = id
        self.turnID = turnID
        self.text = text
        self.sourceRange = sourceRange
    }
}

public struct TranscriptWordIndex: Equatable, Sendable {
    public let words: [TranscriptEditableWord]

    public init(transcript: TurnSegmentedTranscript) throws {
        let spansByID = Dictionary(uniqueKeysWithValues: transcript.spans.map { ($0.id, $0) })
        words = try transcript.turns.flatMap { turn in
            try turn.spanIDs.compactMap { spanID in
                guard let span = spansByID[spanID] else {
                    return nil
                }
                return TranscriptEditableWord(
                    id: span.id,
                    turnID: turn.id,
                    text: span.text,
                    sourceRange: try TimeRange(start: span.start, end: span.end)
                )
            }
        }
    }

    public func visible(with editPlan: TimelineEditPlan) -> [TranscriptEditableWord] {
        words.filter { !editPlan.removes($0.sourceRange) }
    }
}

public struct TranscriptWordCutPlanner: Equatable, Sendable {
    public init() {}

    public func cut(
        transcript: TurnSegmentedTranscript,
        wordID: TranscriptEditableWord.ID,
        trimRange: TimeRange,
        editPlan: TimelineEditPlan,
        minimumRetainedDuration: TimeInterval
    ) throws -> TimelineCut? {
        try cut(
            transcript: transcript,
            wordIDs: [wordID],
            trimRange: trimRange,
            editPlan: editPlan,
            minimumRetainedDuration: minimumRetainedDuration
        )
    }

    public func cut(
        transcript: TurnSegmentedTranscript,
        wordIDs: [TranscriptEditableWord.ID],
        trimRange: TimeRange,
        editPlan: TimelineEditPlan,
        minimumRetainedDuration: TimeInterval
    ) throws -> TimelineCut? {
        let words = try TranscriptWordIndex(transcript: transcript).visible(with: editPlan)
        let selectedIDs = Set(wordIDs)
        let selectedIndexes = words.indices.filter { selectedIDs.contains(words[$0].id) }
        guard let firstIndex = selectedIndexes.first, let lastIndex = selectedIndexes.last else {
            return nil
        }
        guard selectedIndexes == Array(firstIndex...lastIndex) else {
            throw TimelineEditingError.noncontiguousTranscriptSelection
        }
        let selectedWords = Array(words[firstIndex...lastIndex])
        guard let first = selectedWords.first, let last = selectedWords.last else {
            return nil
        }

        let cut = try TimelineCut(
            id: "transcript-\(first.id)-\(last.id)",
            sourceRange: TimeRange(
                start: first.sourceRange.start,
                end: last.sourceRange.end
            ),
            kind: .transcriptSentence,
            transcriptSpanIDs: selectedWords.map(\.id)
        )
        guard
            try editPlan.inserting(
                cut,
                within: trimRange,
                minimumRetainedDuration: minimumRetainedDuration
            ) != nil
        else {
            return nil
        }
        return cut
    }
}
