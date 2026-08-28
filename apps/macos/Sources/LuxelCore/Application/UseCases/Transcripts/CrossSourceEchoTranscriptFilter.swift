import Foundation

enum CrossSourceEchoTranscriptFilter {
    private static let maximumStartDelta: TimeInterval = 0.18

    static func removingEcho(
        from sortedSpans: [TimedTranscriptSpan]
    ) -> [TimedTranscriptSpan] {
        let systemSpans = sortedSpans.filter { $0.source == .system }
        var firstCandidateIndex = 0
        return sortedSpans.filter { span in
            guard span.source == .microphone else {
                return true
            }

            while firstCandidateIndex < systemSpans.count,
                systemSpans[firstCandidateIndex].start < span.start - maximumStartDelta {
                firstCandidateIndex += 1
            }

            var candidateIndex = firstCandidateIndex
            while candidateIndex < systemSpans.count,
                systemSpans[candidateIndex].start <= span.start + maximumStartDelta {
                if isEcho(microphoneSpan: span, systemSpan: systemSpans[candidateIndex]) {
                    return false
                }
                candidateIndex += 1
            }

            return true
        }
    }

    private static func isEcho(
        microphoneSpan: TimedTranscriptSpan,
        systemSpan: TimedTranscriptSpan
    ) -> Bool {
        let boundaryCharacters = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
        let microphoneText = microphoneSpan.text
            .trimmingCharacters(in: boundaryCharacters)
            .lowercased()
        let systemText = systemSpan.text
            .trimmingCharacters(in: boundaryCharacters)
            .lowercased()
        guard !microphoneText.isEmpty, microphoneText == systemText else {
            return false
        }

        let overlap =
            min(microphoneSpan.end, systemSpan.end)
            - max(microphoneSpan.start, systemSpan.start)
        let shorterDuration = min(
            microphoneSpan.end - microphoneSpan.start,
            systemSpan.end - systemSpan.start
        )
        return overlap >= shorterDuration * 0.5
    }
}
