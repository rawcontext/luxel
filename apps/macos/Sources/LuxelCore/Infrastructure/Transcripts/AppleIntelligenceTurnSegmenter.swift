import Foundation
import FoundationModels

public struct AppleIntelligenceTurnSegmenter: TranscriptTurnSegmenter {
    public init() {}

    public func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        let model = SystemLanguageModel.default
        guard model.availability == .available else {
            throw AppleIntelligenceTurnSegmentationError.unavailable
        }

        let chunks = Self.chunks(from: spans)
        var turns: [TranscriptTurn] = []
        for chunk in chunks {
            let chunkTurns = try await segmentChunk(
                chunk,
                locale: locale,
                model: model,
                retrying: false
            )
            turns.append(contentsOf: chunkTurns)
        }

        let normalizedTurns = try turns.enumerated().map { index, turn in
            try TranscriptTurn(
                id: "turn-\(index)",
                spanIDs: turn.spanIDs,
                start: turn.start,
                end: turn.end,
                text: turn.text,
                source: turn.source
            )
        }

        return try TurnSegmentedTranscript(
            spans: spans,
            turns: normalizedTurns,
            localeIdentifier: locale.identifier
        )
    }

    private func segmentChunk(
        _ spans: [TimedTranscriptSpan],
        locale: Locale,
        model: SystemLanguageModel,
        retrying: Bool
    ) async throws -> [TranscriptTurn] {
        let session = LanguageModelSession(
            model: model,
            instructions: retrying ? Self.retryInstructions : Self.instructions
        )
        let response = try await session.respond(
            to: Self.prompt(for: spans, locale: locale, retrying: retrying),
            generating: GeneratedTurnSegmentedTranscript.self,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0,
                maximumResponseTokens: max(512, spans.count * 32)
            )
        )

        do {
            let transcript = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                candidates: response.content.turns.map(Self.candidate(from:)),
                localeIdentifier: locale.identifier
            )
            return transcript.turns
        } catch {
            guard !retrying else {
                throw error
            }

            return try await segmentChunk(
                spans,
                locale: locale,
                model: model,
                retrying: true
            )
        }
    }

    private static func candidate(from turn: GeneratedTranscriptTurn) throws
    -> TranscriptTurnCandidate {
        TranscriptTurnCandidate(
            id: turn.id,
            spanIDs: turn.spanIDs,
            start: turn.start,
            end: turn.end,
            text: turn.text,
            source: try sourceLabel(from: turn.source)
        )
    }

    private static func sourceLabel(from source: String?) throws -> TranscriptSourceLabel? {
        guard let source else {
            return nil
        }

        switch source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "unknown", "none", "nil":
            return nil
        case "system", "system audio":
            return .system
        case "microphone", "mic":
            return .microphone
        default:
            throw TranscriptModelError.inventedSource(source)
        }
    }

    private static func prompt(
        for spans: [TimedTranscriptSpan],
        locale: Locale,
        retrying: Bool
    ) -> String {
        let retryText =
            retrying
            ? """

      Your previous response failed validation. This time preserve every span id exactly once,
      keep the text exact, and do not invent sources.

      """
            : ""
        let spanLines = spans.map { span in
            let source = span.source?.rawValue ?? "unknown"
            return
                """
        [id=\(span.id) start=\(formatTime(span.start)) end=\(formatTime(span.end)) \
        source=\(source)] \(sanitized(span.text))
        """
        }.joined(separator: "\n")

        return """
      Segment this \(locale.identifier) time-coded transcript into display turns.\(retryText)

      Input spans:
      \(spanLines)

      Return structured turns only.
      """
    }

    private static var instructions: String {
        """
    You segment a time-coded transcript into conversational turns for display.

    You are not performing speaker diarization. Do not identify speakers from voice, wording, names,
    gender, role, or topic. Use only provided source labels.
    If a span has source=microphone, its display source is Microphone.
    If source=system, its display source is System Audio.
    If source is missing or unknown, leave the turn source empty unless every span in the turn has the
    same known source.

    Preserve the transcript exactly:
    - Do not add, remove, rewrite, summarize, translate, censor, normalize, or correct words.
    - Keep spans in their original order.
    - Every input span id must appear in exactly one output turn.
    - Turn text must be the exact joined text of its span ids, using normal single spaces between spans.
    - Do not create speaker names.

    Create a new turn when one or more of these strongly suggests a conversational boundary:
    - The source label changes between adjacent spans.
    - There is a pause of about 1.2 seconds or longer.
    - A question is followed by an answer.
    - The semantic focus changes from one participant/action to another.
    - A short acknowledgment is clearly its own response.

    Prefer fewer, larger turns when uncertain. Keep brief filler words or backchannels inside the surrounding
    turn unless they clearly form a separate response.
    """
    }

    private static var retryInstructions: String {
        """
    You repair transcript turn segmentation output. Follow these constraints exactly:
    - Use every input span id exactly once in original order.
    - Do not change transcript text.
    - Use only source values from the input: system, microphone, or nil.
    - Do not infer speakers or names.
    - Prefer fewer turns when uncertain.
    """
    }

    private static func chunks(from spans: [TimedTranscriptSpan]) -> [[TimedTranscriptSpan]] {
        var chunks: [[TimedTranscriptSpan]] = []
        var current: [TimedTranscriptSpan] = []
        var currentCharacterCount = 0

        for span in spans {
            let projectedCharacterCount = currentCharacterCount + span.text.count
            if !current.isEmpty,
               current.count >= 220 || projectedCharacterCount > 10_000,
               shouldBreakBefore(span, after: current[current.count - 1]) {
                chunks.append(current)
                current = []
                currentCharacterCount = 0
            }

            current.append(span)
            currentCharacterCount += span.text.count
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func shouldBreakBefore(
        _ span: TimedTranscriptSpan,
        after previousSpan: TimedTranscriptSpan
    ) -> Bool {
        span.start - previousSpan.end >= 1.2 || span.source != previousSpan.source
    }

    private static func sanitized(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), time)
    }
}

@Generable
private struct GeneratedTurnSegmentedTranscript {
    let turns: [GeneratedTranscriptTurn]
}

@Generable
private struct GeneratedTranscriptTurn {
    let id: String
    let spanIDs: [String]
    let start: Double
    let end: Double
    let text: String
    let source: String?
}

public enum AppleIntelligenceTurnSegmentationError: Error, Equatable, Sendable {
    case unavailable
}
