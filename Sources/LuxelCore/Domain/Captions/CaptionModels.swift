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

public struct RecognizedWord: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let text: String
    public let confidence: Double

    public init(
        start: TimeInterval,
        duration: TimeInterval,
        text: String,
        confidence: Double
    ) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw CaptionModelError.invalidRecognizedWord
        }

        guard start >= 0, start.isFinite, duration > 0, duration.isFinite else {
            throw CaptionModelError.invalidRecognizedWord
        }

        guard confidence >= 0, confidence <= 1, confidence.isFinite else {
            throw CaptionModelError.invalidConfidence
        }

        self.timeRange = try TimeRange(start: start, end: start + duration)
        self.text = normalizedText
        self.confidence = confidence
    }
}

public struct CaptionCueBuilderConfiguration: Equatable, Sendable {
    public let maxCharactersPerLine: Int
    public let maxLines: Int
    public let minimumDuration: TimeInterval
    public let maximumDuration: TimeInterval
    public let speechPauseThreshold: TimeInterval

    public static let standard = CaptionCueBuilderConfiguration(
        uncheckedMaxCharactersPerLine: 42,
        maxLines: 2,
        minimumDuration: 0.8,
        maximumDuration: 6,
        speechPauseThreshold: 0.6
    )

    public init(
        maxCharactersPerLine: Int = 42,
        maxLines: Int = 2,
        minimumDuration: TimeInterval = 0.8,
        maximumDuration: TimeInterval = 6,
        speechPauseThreshold: TimeInterval = 0.6
    ) throws {
        guard maxCharactersPerLine > 0,
              maxLines > 0,
              minimumDuration > 0,
              minimumDuration.isFinite,
              maximumDuration >= minimumDuration,
              maximumDuration.isFinite,
              speechPauseThreshold >= 0,
              speechPauseThreshold.isFinite else {
            throw CaptionModelError.invalidCueBuilderConfiguration
        }

        self.init(
            uncheckedMaxCharactersPerLine: maxCharactersPerLine,
            maxLines: maxLines,
            minimumDuration: minimumDuration,
            maximumDuration: maximumDuration,
            speechPauseThreshold: speechPauseThreshold
        )
    }

    private init(
        uncheckedMaxCharactersPerLine maxCharactersPerLine: Int,
        maxLines: Int,
        minimumDuration: TimeInterval,
        maximumDuration: TimeInterval,
        speechPauseThreshold: TimeInterval
    ) {
        self.maxCharactersPerLine = maxCharactersPerLine
        self.maxLines = maxLines
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
        self.speechPauseThreshold = speechPauseThreshold
    }
}

public struct CaptionCueBuilder: Sendable {
    public let configuration: CaptionCueBuilderConfiguration

    public init(
        configuration: CaptionCueBuilderConfiguration = .standard
    ) {
        self.configuration = configuration
    }

    public func buildCues(from words: [RecognizedWord]) throws -> [CaptionCue] {
        guard !words.isEmpty else {
            return []
        }

        try validateSorted(words)

        var cues: [CaptionCue] = []
        var pendingWords: [RecognizedWord] = []

        for word in words {
            if pendingWords.isEmpty {
                pendingWords.append(word)
                continue
            }

            if shouldStartNewCue(before: word, pendingWords: pendingWords) {
                cues.append(try cue(from: pendingWords, endingBefore: word.timeRange.start))
                pendingWords = [word]
                continue
            }

            pendingWords.append(word)

            if shouldEndCue(after: word, pendingWords: pendingWords) {
                cues.append(try cue(from: pendingWords))
                pendingWords = []
            }
        }

        if !pendingWords.isEmpty {
            cues.append(try cue(from: pendingWords))
        }

        return cues
    }

    private func validateSorted(_ words: [RecognizedWord]) throws {
        for pair in zip(words, words.dropFirst()) where pair.1.timeRange.start < pair.0.timeRange.start {
            throw CaptionModelError.unsortedRecognizedWords
        }
    }

    private func shouldStartNewCue(
        before word: RecognizedWord,
        pendingWords: [RecognizedWord]
    ) -> Bool {
        guard let lastWord = pendingWords.last else {
            return false
        }

        let gap = word.timeRange.start - lastWord.timeRange.end
        if gap >= configuration.speechPauseThreshold {
            return true
        }

        let candidateWords = pendingWords + [word]
        return duration(from: candidateWords) > configuration.maximumDuration
            || text(for: candidateWords) == nil
    }

    private func shouldEndCue(
        after word: RecognizedWord,
        pendingWords: [RecognizedWord]
    ) -> Bool {
        sentenceTerminators.contains(where: word.text.hasSuffix)
            && duration(from: pendingWords) >= configuration.minimumDuration
    }

    private var sentenceTerminators: [String] {
        [".", "?", "!"]
    }

    private func duration(from words: [RecognizedWord]) -> TimeInterval {
        guard let first = words.first, let last = words.last else {
            return 0
        }

        return last.timeRange.end - first.timeRange.start
    }

    private func cue(
        from words: [RecognizedWord],
        endingBefore nextStart: TimeInterval? = nil
    ) throws -> CaptionCue {
        guard let first = words.first, let last = words.last, let text = text(for: words) else {
            throw CaptionModelError.invalidCueText
        }

        let minimumEnd = first.timeRange.start + configuration.minimumDuration
        var end = max(last.timeRange.end, minimumEnd)
        if let nextStart {
            end = min(end, nextStart)
        }

        return try CaptionCue(
            timeRange: TimeRange(start: first.timeRange.start, end: end),
            text: text
        )
    }

    private func text(for words: [RecognizedWord]) -> String? {
        CaptionLineWrapper(
            maxCharactersPerLine: configuration.maxCharactersPerLine,
            maxLines: configuration.maxLines
        ).wrap(words.map(\.text).joined(separator: " "))
    }
}

private struct CaptionLineWrapper {
    let maxCharactersPerLine: Int
    let maxLines: Int

    func wrap(_ text: String) -> String? {
        var lines: [String] = []
        var currentLine = ""

        for word in text.split(separator: " ").map(String.init) {
            for token in tokens(for: word) {
                if currentLine.isEmpty {
                    currentLine = token
                } else if currentLine.count + 1 + token.count <= maxCharactersPerLine {
                    currentLine += " \(token)"
                } else {
                    lines.append(currentLine)
                    currentLine = token
                }

                guard lines.count < maxLines else {
                    return nil
                }
            }
        }

        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.count <= maxLines ? lines.joined(separator: "\n") : nil
    }

    private func tokens(for word: String) -> [String] {
        guard word.count > maxCharactersPerLine else {
            return [word]
        }

        var tokens: [String] = []
        var startIndex = word.startIndex
        while startIndex < word.endIndex {
            let endIndex = word.index(
                startIndex,
                offsetBy: maxCharactersPerLine,
                limitedBy: word.endIndex
            ) ?? word.endIndex
            tokens.append(String(word[startIndex..<endIndex]))
            startIndex = endIndex
        }
        return tokens
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
    case invalidRecognizedWord
    case invalidConfidence
    case invalidCueBuilderConfiguration
    case unsortedRecognizedWords
}
