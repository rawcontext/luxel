import FluidAudio
import Foundation

public enum PrecisionTranscriptionError: Error, Equatable, Sendable {
    case modelNotInstalled
    case modelCorrupt
    case unsupportedLanguage(String)
    case unsupportedHardware
    case missingTokenTimings
    case invalidTokenTimings
    case textReconstructionMismatch
    case inferenceFailed
    case appleCaptionTranscriberUnavailable
}

extension PrecisionTranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "Precision Transcription is not installed. Open Settings to download it or switch to Apple Speech."
        case .modelCorrupt:
            "The Precision Transcription model needs repair. Re-download it in Settings or switch to Apple Speech."
        case .unsupportedLanguage(let code):
            "Precision Transcription does not support \(code). Choose a supported language or switch to Apple Speech."
        case .unsupportedHardware:
            "Precision Transcription requires Apple silicon. Switch to Apple Speech on this Mac."
        case .missingTokenTimings, .invalidTokenTimings, .textReconstructionMismatch:
            "Precision Transcription returned invalid word timings. Retry or switch to Apple Speech."
        case .inferenceFailed:
            "Precision Transcription failed. Retry or switch to Apple Speech."
        case .appleCaptionTranscriberUnavailable:
            "Caption transcription is not available with Apple Speech in this version of Luxel."
        }
    }
}

public enum PrecisionTranscriptionLanguageCatalog {
    public static let supportedCodes: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu",
        "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
    ]

    public static func languageCode(for locale: Locale) throws -> Locale.LanguageCode {
        guard let languageCode = locale.language.languageCode,
              supportedCodes.contains(languageCode.identifier.lowercased())
        else {
            let requested = locale.language.languageCode?.identifier ?? locale.identifier
            throw PrecisionTranscriptionError.unsupportedLanguage(requested)
        }
        return languageCode
    }

    static func fluidLanguage(for locale: Locale) throws -> Language {
        let languageCode = try languageCode(for: locale)
        guard let language = Language(rawValue: languageCode.identifier.lowercased()) else {
            throw PrecisionTranscriptionError.unsupportedLanguage(languageCode.identifier)
        }
        return language
    }
}

public struct PrecisionTokenTiming: Equatable, Sendable {
    public let token: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(token: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.token = token
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct PrecisionRecognizedWord: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }

    public func timedSpan(id: String, source: TranscriptSourceLabel?) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            confidence: confidence,
            source: source
        )
    }

    public func captionWord() throws -> RecognizedWord {
        try RecognizedWord(
            start: start,
            duration: end - start,
            text: text,
            confidence: confidence
        )
    }
}

public enum PrecisionTokenTimingMapper {
    private static let boundary = "▁"
    private static let epsilon: TimeInterval = 0.001
    private static let ignoredTokens: Set<String> = ["", "<blank>", "<pad>"]

    public static func map(
        _ timings: [PrecisionTokenTiming],
        expectedText: String
    ) throws -> [PrecisionRecognizedWord] {
        let content = timings.filter { !ignoredTokens.contains($0.token) }
        guard !content.isEmpty else {
            guard normalize(expectedText).isEmpty else {
                throw PrecisionTranscriptionError.missingTokenTimings
            }
            return []
        }
        let validated = try validatedTimings(content)
        let decoded = validated.map(\.token).joined()
            .replacingOccurrences(of: boundary, with: " ")
        guard normalize(decoded) == normalize(expectedText) else {
            throw PrecisionTranscriptionError.textReconstructionMismatch
        }
        let words = try recognizedWords(from: groupedTimings(validated))
        let adjustedWords = try adjustedWords(words)
        guard normalize(adjustedWords.map(\.text).joined(separator: " ")) == normalize(expectedText)
        else {
            throw PrecisionTranscriptionError.textReconstructionMismatch
        }
        return adjustedWords
    }

    private static func validatedTimings(
        _ timings: [PrecisionTokenTiming]
    ) throws -> [PrecisionTokenTiming] {
        try timings.map { timing in
            guard timing.start.isFinite,
                  timing.end.isFinite,
                  timing.confidence.isFinite,
                  timing.start >= 0,
                  timing.end > timing.start,
                  (0...1).contains(timing.confidence)
            else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }
            return timing
        }
    }

    private static func groupedTimings(
        _ validated: [PrecisionTokenTiming]
    ) -> [[PrecisionTokenTiming]] {
        var groups: [[PrecisionTokenTiming]] = []
        for timing in validated {
            let startsWord =
                timing.token.hasPrefix(boundary)
                || timing.token.first?.isWhitespace == true
            if startsWord || groups.isEmpty {
                groups.append([timing])
            } else {
                groups[groups.count - 1].append(timing)
            }
        }
        return groups
    }

    private static func recognizedWords(
        from groups: [[PrecisionTokenTiming]]
    ) throws -> [PrecisionRecognizedWord] {
        try groups.map { group in
            let text = group.map(\.token).joined()
                .replacingOccurrences(of: boundary, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty,
                  let start = group.map(\.start).min(),
                  let end = group.map(\.end).max()
            else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }
            let totalDuration = group.reduce(0) { $0 + ($1.end - $1.start) }
            guard totalDuration > 0 else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }
            let confidence =
                group.reduce(0) {
                    $0 + $1.confidence * ($1.end - $1.start)
                } / totalDuration
            return PrecisionRecognizedWord(
                text: text,
                start: start,
                end: end,
                confidence: confidence
            )
        }
    }

    private static func adjustedWords(
        _ words: [PrecisionRecognizedWord]
    ) throws -> [PrecisionRecognizedWord] {
        var adjustedWords: [PrecisionRecognizedWord] = []
        var previousEnd: TimeInterval?
        for word in words {
            var start = word.start
            if let previousEnd, start < previousEnd {
                guard previousEnd - start <= epsilon, word.end > previousEnd else {
                    throw PrecisionTranscriptionError.invalidTokenTimings
                }
                start = previousEnd
            }
            let adjusted = PrecisionRecognizedWord(
                text: word.text,
                start: start,
                end: word.end,
                confidence: word.confidence
            )
            adjustedWords.append(adjusted)
            previousEnd = adjusted.end
        }
        return adjustedWords
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PrecisionRecognitionResult: Equatable, Sendable {
    public let text: String
    public let words: [PrecisionRecognizedWord]
    public let language: Locale.LanguageCode
    public let confidence: Double
    public let provenance: TranscriptionProvenance

    public init(
        text: String,
        words: [PrecisionRecognizedWord],
        language: Locale.LanguageCode,
        confidence: Double,
        provenance: TranscriptionProvenance
    ) {
        self.text = text
        self.words = words
        self.language = language
        self.confidence = confidence
        self.provenance = provenance
    }
}

public protocol PrecisionRecognizing: Sendable {
    func recognize(
        audioURL: URL,
        audioTrackIndex: Int?,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PrecisionRecognitionResult
}
