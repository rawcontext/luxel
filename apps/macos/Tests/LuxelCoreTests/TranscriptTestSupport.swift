import LuxelCore

func sampleTestTranscript(
    text: String,
    source: TranscriptSourceLabel?
) throws -> TurnSegmentedTranscript {
    let span = try TimedTranscriptSpan(
        id: "span-0",
        text: text,
        start: 0,
        end: 0.5,
        source: source
    )
    return try TurnSegmentedTranscript(
        spans: [span],
        turns: [
            TranscriptTurn(
                id: "turn-0",
                spanIDs: [span.id],
                start: span.start,
                end: span.end,
                text: span.text,
                source: source
            )
        ],
        localeIdentifier: "en_US"
    )
}
