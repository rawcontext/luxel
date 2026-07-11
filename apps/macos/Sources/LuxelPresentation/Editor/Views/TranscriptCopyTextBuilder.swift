import LuxelCore

struct TranscriptCopyTextBuilder {
    func text(
        transcript: TurnSegmentedTranscript,
        visibleSentences: [TranscriptEditableSentence],
        hasCuts: Bool
    ) -> String {
        transcript.turns.compactMap { turn -> String? in
            let turnText = hasCuts
                ? visibleSentences
                .filter { $0.turnID == turn.id }
                .map(\.text)
                .joined(separator: " ")
                : turn.text
            guard !turnText.isEmpty else {
                return nil
            }
            guard !transcript.speakers.isEmpty else {
                return turnText
            }

            var labels: [String] = []
            if let speaker = transcript.speaker(for: turn.speakerID) {
                labels.append(speaker.displayName)
            }
            if let source = turn.source {
                labels.append(source.displayName)
            }
            return labels.isEmpty ? turnText : "\(labels.joined(separator: " — ")): \(turnText)"
        }
        .joined(separator: "\n\n")
    }
}
