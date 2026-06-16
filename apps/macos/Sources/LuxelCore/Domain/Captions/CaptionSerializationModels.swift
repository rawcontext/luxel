import Foundation

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

public enum CaptionFileFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case srt
    case vtt
    case plainText

    public var fileExtension: String {
        switch self {
        case .srt:
            "srt"
        case .vtt:
            "vtt"
        case .plainText:
            "txt"
        }
    }

    public func serialize(_ track: CaptionTrack) -> String {
        switch self {
        case .srt:
            SRTCaptionSerializer.serialize(track)
        case .vtt:
            VTTCaptionSerializer.serialize(track)
        case .plainText:
            PlainTextCaptionSerializer.serialize(track)
        }
    }
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

public enum PlainTextCaptionSerializer {
    public static func serialize(_ track: CaptionTrack) -> String {
        guard !track.cues.isEmpty else {
            return ""
        }

        return track.cues.map(\.text).joined(separator: "\n\n") + "\n"
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
    case invalidRecognizedWord
    case invalidConfidence
    case invalidCueBuilderConfiguration
    case unsortedRecognizedWords
    case unsupportedSidecarSchemaVersion
    case invalidCueIndex
    case invalidCueSplitTime
}
