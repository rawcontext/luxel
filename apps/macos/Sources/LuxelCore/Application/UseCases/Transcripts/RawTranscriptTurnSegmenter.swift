import Foundation

public struct RawTranscriptTurnSegmenter: TranscriptTurnSegmenter {
    private static let maximumTurnSpanCount = 80

    public init() {}

    public func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            turnSpanIDs: Self.turnSpanIDs(from: spans),
            localeIdentifier: locale.identifier
        )
    }

    static func turnSpanIDs(from spans: [TimedTranscriptSpan]) -> [[String]] {
        var groups: [[TimedTranscriptSpan]] = []
        var current: [TimedTranscriptSpan] = []

        for span in spans {
            if let last = current.last,
                current.count >= maximumTurnSpanCount
                    || last.source != span.source
                    || last.speakerID != span.speakerID
            {
                groups.append(current)
                current = []
            }

            current.append(span)
        }

        if !current.isEmpty {
            groups.append(current)
        }

        return groups.map { $0.map(\.id) }
    }
}
