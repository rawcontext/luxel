import LuxelCore

struct TranscriptCopyTextBuilder {
    func text(
        transcript: TurnSegmentedTranscript,
        visibleWords: [TranscriptEditableWord],
        hasCuts: Bool
    ) -> String {
        transcript.turns.compactMap { turn -> String? in
            let turnText = hasCuts
                ? visibleWords
                .filter { $0.turnID == turn.id }
                .map(\.text)
                .joined(separator: " ")
                : turn.text
            guard !turnText.isEmpty else {
                return nil
            }
            return LuxelTranscriptFormatter.labeledText(turnText, for: turn, in: transcript)
        }
        .joined(separator: "\n\n")
    }
}
