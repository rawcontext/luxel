import Foundation
import NaturalLanguage

public enum RecordingTitleModelAvailability: Equatable, Sendable {
    case available
    case notEnabled
    case downloading
    case unsupported
    case unavailable
}

public protocol RecordingTitleGenerator: Sendable {
    var availability: RecordingTitleModelAvailability { get }
    func title(from transcriptPrefix: String) async throws -> String
}

public enum RecordingTitlePolicy {
    public static let maximumWords = 200

    public static func isEnabled(preference: Bool?, availability: RecordingTitleModelAvailability) -> Bool {
        preference ?? (availability == .available)
    }

    public static func transcriptPrefix(_ transcript: TurnSegmentedTranscript) -> String {
        prefix(spans: transcript.spans, localeIdentifier: transcript.localeIdentifier).text
    }

    public static func prefix(
        spans: [TimedTranscriptSpan], localeIdentifier: String
    ) -> (text: String, wordCount: Int) {
        let text = spans.enumerated().sorted {
            $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start
        }.map(\.element.text).joined(separator: " ")
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let language = localeIdentifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first
        if let language { tokenizer.setLanguage(NLLanguage(rawValue: String(language))) }
        var count = 0
        var end = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            count += 1
            end = range.upperBound
            return count < maximumWords
        }
        return (String(text[..<end]), count)
    }

    public static func validatedTitle(_ output: String) -> String? {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 72,
            !text.contains(where: \.isNewline),
            text.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\:*?\"<>|`#[]{}.“”‘’")) == nil,
            !text.hasPrefix("-"), !text.hasPrefix("'"), !text.hasSuffix("'"),
            !text.contains(".."),
            text.range(
                of: #"\b\d{4}[-.]\d{2}[-.]\d{2}\b|\.(mp4|mov|m4a|wav|webm|md|txt)$"#,
                options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        let count = tokenizer.tokens(for: text.startIndex..<text.endIndex).count
        guard (1...9).contains(count) else { return nil }
        let title = RecordingFileLayout.sanitizedTitle(text)
        return title.isEmpty ? nil : title
    }
}
