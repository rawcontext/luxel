import Foundation

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
            speechPauseThreshold.isFinite
        else {
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
            let endIndex =
                word.index(
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
