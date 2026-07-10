import Foundation

public enum LuxelTranscriptFormatter {
    public static func plainText(_ transcript: TurnSegmentedTranscript) -> String {
        transcript.turns.map { turn in
            guard !transcript.speakers.isEmpty else {
                return turn.text
            }

            var labels: [String] = []
            if let speaker = transcript.speaker(for: turn.speakerID) {
                labels.append(speaker.displayName)
            }
            if let source = turn.source {
                labels.append(source.displayName)
            }

            guard !labels.isEmpty else {
                return turn.text
            }
            return "\(labels.joined(separator: " — ")): \(turn.text)"
        }
        .joined(separator: "\n")
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
