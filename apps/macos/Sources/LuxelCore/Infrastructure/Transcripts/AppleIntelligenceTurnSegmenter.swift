import Foundation
import FoundationModels

public struct AppleIntelligenceTurnSegmenter: TranscriptTurnSegmenter {
    private static let maximumChunkSpanCount = 80
    private static let maximumChunkCharacterCount = 4_000

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

        let response: LanguageModelSession.Response<GeneratedTurnSegmentedTranscript>
        do {
            response = try await session.respond(
                to: Self.prompt(for: spans, locale: locale, retrying: retrying),
                generating: GeneratedTurnSegmentedTranscript.self,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0,
                    maximumResponseTokens: max(256, spans.count * 24)
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard spans.count > 1 else {
                throw error
            }

            return try await segmentSplitChunk(spans, locale: locale, model: model)
        }

        do {
            let transcript = try TranscriptSegmentationValidator.makeTranscript(
                spans: spans,
                turnSpanIDs: response.content.turns.map(\.spanIDs),
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

    private func segmentSplitChunk(
        _ spans: [TimedTranscriptSpan],
        locale: Locale,
        model: SystemLanguageModel
    ) async throws -> [TranscriptTurn] {
        let splitIndex = Self.splitIndex(for: spans)
        let leadingSpans = Array(spans[..<splitIndex])
        let trailingSpans = Array(spans[splitIndex...])
        let leadingTurns = try await segmentChunk(
            leadingSpans,
            locale: locale,
            model: model,
            retrying: false
        )
        let trailingTurns = try await segmentChunk(
            trailingSpans,
            locale: locale,
            model: model,
            retrying: false
        )
        return leadingTurns + trailingTurns
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
      return only ordered span id groups. The app will reconstruct exact text, timing, and source.

      """
            : ""
        let spanLines = spans.map { span in
            let source = span.source?.rawValue ?? "unknown"
            return
                """
        [id=\(span.id) start=\(formatTime(span.start)) end=\(formatTime(span.end)) \
        source=\(source)] \(retrying ? "" : sanitized(span.text))
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

    Group the transcript exactly:
    - Keep spans in their original order.
    - Every input span id must appear in exactly one output turn.
    - Do not create speaker names, speaker ids, source labels, text, timing, summaries, or corrections.
    - Return only turn ids and ordered span id lists.

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
    - Return only turn ids and ordered span id lists.
    - Do not infer speakers, names, text, timing, or source labels.
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
               current.count >= maximumChunkSpanCount
                || projectedCharacterCount > maximumChunkCharacterCount {
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

    private static func splitIndex(for spans: [TimedTranscriptSpan]) -> Int {
        let midpoint = spans.count / 2
        guard spans.count > 2 else {
            return 1
        }

        if let naturalSplitIndex = spans.indices.dropFirst().min(by: { lhs, rhs in
            let lhsScore = splitScore(before: lhs, midpoint: midpoint, spans: spans)
            let rhsScore = splitScore(before: rhs, midpoint: midpoint, spans: spans)
            return lhsScore < rhsScore
        }) {
            return naturalSplitIndex
        }

        return midpoint
    }

    private static func splitScore(
        before index: Int,
        midpoint: Int,
        spans: [TimedTranscriptSpan]
    ) -> Double {
        let previousSpan = spans[index - 1]
        let span = spans[index]
        let distancePenalty = Double(abs(index - midpoint))
        let boundaryBonus =
            span.start - previousSpan.end >= 1.2 || span.source != previousSpan.source
            ? -1_000.0
            : 0
        return distancePenalty + boundaryBonus
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
    let spanIDs: [String]
}

public enum AppleIntelligenceTurnSegmentationError: Error, Equatable, Sendable {
    case unavailable
}
