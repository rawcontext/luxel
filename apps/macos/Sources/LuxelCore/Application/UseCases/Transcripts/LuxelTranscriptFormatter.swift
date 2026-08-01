import Foundation

public enum LuxelTranscriptFormatter {
    public static func plainText(_ transcript: TurnSegmentedTranscript) -> String {
        transcript.turns.map { turn in
            labeledText(turn.text, for: turn, in: transcript)
        }
        .joined(separator: "\n")
    }

    public static func labeledText(
        _ text: String,
        for turn: TranscriptTurn,
        in transcript: TurnSegmentedTranscript
    ) -> String {
        guard !transcript.speakers.isEmpty else {
            return text
        }

        let labels = [
            transcript.speaker(for: turn.speakerID)?.displayName,
            turn.source?.displayName
        ].compactMap { $0 }
        return labels.isEmpty ? text : "\(labels.joined(separator: " — ")): \(text)"
    }

    public static func data(
        for transcript: TurnSegmentedTranscript,
        json: Bool
    ) throws -> Data {
        var data: Data
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(transcript)
        } else {
            data = Data(plainText(transcript).utf8)
        }
        if data.last != 0x0a {
            data.append(0x0a)
        }
        return data
    }
}
