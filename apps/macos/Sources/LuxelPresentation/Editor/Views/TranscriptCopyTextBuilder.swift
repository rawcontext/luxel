import LuxelCore

struct TranscriptCopyTextBuilder {
    func text(
        transcript: TurnSegmentedTranscript,
        visibleWords: [TranscriptEditableWord],
        hasCuts: Bool
    ) -> String {
        transcript.turns.compactMap { turn -> String? in
            let turnText =
                hasCuts
                ? visibleWords
                    .filter { $0.turnID == turn.id }
                    .map(\.text)
                    .joined(separator: " ")
                : turn.text
            guard !turnText.isEmpty else {
                return nil
            }
            guard let speaker = transcript.speaker(for: turn.speakerID) else {
                return turnText
            }
            return "\(speaker.displayName): \(turnText)"
        }
        .joined(separator: "\n\n")
    }
}
