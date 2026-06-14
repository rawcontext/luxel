import Foundation

public struct CaptionCue: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let text: String

    public init(timeRange: TimeRange, text: String) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw CaptionModelError.invalidCueText
        }

        let lines = normalizedText.components(separatedBy: .newlines)
        guard lines.count <= 2, lines.allSatisfy({ !$0.isEmpty }) else {
            throw CaptionModelError.tooManyCueLines
        }

        self.timeRange = timeRange
        self.text = normalizedText
    }
}

public struct CaptionTrack: Codable, Equatable, Sendable {
    public let cues: [CaptionCue]
    public let language: Locale.LanguageCode
    public let sourceTrack: AudioTrackKind?

    public init(
        cues: [CaptionCue],
        language: Locale.LanguageCode,
        sourceTrack: AudioTrackKind? = nil
    ) throws {
        try Self.validate(cues)

        self.cues = cues
        self.language = language
        self.sourceTrack = sourceTrack
    }

    private static func validate(_ cues: [CaptionCue]) throws {
        for pair in zip(cues, cues.dropFirst()) {
            if pair.1.timeRange.start < pair.0.timeRange.start {
                throw CaptionModelError.unsortedCues
            }

            if pair.1.timeRange.start < pair.0.timeRange.end {
                throw CaptionModelError.overlappingCues
            }
        }
    }
}

public struct CaptionRenderOptions: Codable, Equatable, Sendable {
    public let burnIn: Bool
    public let position: CaptionPosition
    public let size: CaptionSize
    public let theme: CaptionTheme

    public init(
        burnIn: Bool = false,
        position: CaptionPosition = .lowerThird,
        size: CaptionSize = .medium,
        theme: CaptionTheme = .darkGlass
    ) {
        self.burnIn = burnIn
        self.position = position
        self.size = size
        self.theme = theme
    }
}

public enum CaptionPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case lowerThird
    case top
}

public enum CaptionSize: String, Codable, CaseIterable, Equatable, Sendable {
    case small
    case medium
    case large
}

public enum CaptionTheme: String, Codable, CaseIterable, Equatable, Sendable {
    case darkGlass
    case outlinedText
    case highContrast
}

public enum SRTCaptionSerializer {
    public static func serialize(_ track: CaptionTrack) -> String {
        guard !track.cues.isEmpty else {
            return ""
        }

        return track.cues.enumerated().map { index, cue in
            [
                "\(index + 1)",
                "\(timestamp(cue.timeRange.start, separator: ",")) --> \(timestamp(cue.timeRange.end, separator: ","))",
                cue.text
            ].joined(separator: "\n")
        }.joined(separator: "\n\n") + "\n"
    }

    private static func timestamp(_ time: TimeInterval, separator: String) -> String {
        CaptionTimestampFormatter.timestamp(time, millisecondSeparator: separator)
    }
}

public enum VTTCaptionSerializer {
    public static func serialize(_ track: CaptionTrack) -> String {
        let body = track.cues.map { cue in
            [
                "\(timestamp(cue.timeRange.start, separator: ".")) --> \(timestamp(cue.timeRange.end, separator: "."))",
                cue.text
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")

        return body.isEmpty ? "WEBVTT\n" : "WEBVTT\n\n\(body)\n"
    }

    private static func timestamp(_ time: TimeInterval, separator: String) -> String {
        CaptionTimestampFormatter.timestamp(time, millisecondSeparator: separator)
    }
}

private enum CaptionTimestampFormatter {
    static func timestamp(_ time: TimeInterval, millisecondSeparator: String) -> String {
        let totalMilliseconds = max(0, Int((time * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return [
            twoDigits(hours),
            twoDigits(minutes),
            "\(twoDigits(seconds))\(millisecondSeparator)\(threeDigits(milliseconds))"
        ].joined(separator: ":")
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func threeDigits(_ value: Int) -> String {
        if value < 10 {
            return "00\(value)"
        }

        if value < 100 {
            return "0\(value)"
        }

        return "\(value)"
    }
}

public enum CaptionModelError: Error, Equatable {
    case invalidCueText
    case tooManyCueLines
    case unsortedCues
    case overlappingCues
}
