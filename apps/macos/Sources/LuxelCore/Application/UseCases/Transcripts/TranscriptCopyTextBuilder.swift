import Foundation

public struct TranscriptMarkdownMetadata: Equatable {
    let title: String
    let sourceFileName: String?
    let recordedAt: Date?
    let duration: TimeInterval?

    public init(
        title: String,
        sourceFileName: String?,
        recordedAt: Date?,
        duration: TimeInterval?
    ) {
        self.title = title
        self.sourceFileName = sourceFileName
        self.recordedAt = recordedAt
        self.duration = duration
    }

    public init(source: SourceMedia) {
        self.init(sourceURL: source.fileURL, duration: source.duration)
    }

    public init(sourceURL: URL, duration: TimeInterval? = nil) {
        let fileName = sourceURL.lastPathComponent
        let title = sourceURL.deletingPathExtension().lastPathComponent
        let resourceValues = try? sourceURL.resourceValues(forKeys: [.creationDateKey])

        self.init(
            title: title.isEmpty ? fileName : title,
            sourceFileName: fileName,
            recordedAt: resourceValues?.creationDate,
            duration: duration
        )
    }
}

public struct TranscriptCopyTextBuilder {
    public init() {}

    public func text(
        transcript: TurnSegmentedTranscript,
        visibleWords: [TranscriptEditableWord],
        hasCuts: Bool,
        metadata: TranscriptMarkdownMetadata,
        includesTimestamps: Bool = false,
        exportedAt: Date = Date()
    ) -> String {
        let renderedTurns = transcript.turns.compactMap { turn -> (TranscriptTurn, String)? in
            let turnText =
                hasCuts
                ? visibleWords
                    .filter { $0.turnID == turn.id }
                    .map(\.text)
                    .joined(separator: " ")
                : turn.text
            guard !turnText.isEmpty else {
                return nil
            }
            return (turn, turnText)
        }

        let frontMatter = frontMatter(
            transcript: transcript,
            metadata: metadata,
            exportedAt: exportedAt,
            hasCuts: hasCuts
        )

        let body = renderedTurns.map { turn, turnText in
            let header = [
                transcript.speaker(for: turn.speakerID).map { speaker in
                    "**\(escapedMarkdown(speaker.displayName))**"
                },
                includesTimestamps ? "`\(formatTimestamp(turn.start))`" : nil
            ].compactMap { $0 }.joined(separator: " · ")
            return [header, escapedMarkdown(turnText)]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
        }

        return ([frontMatter.joined(separator: "\n"), "# \(escapedMarkdown(metadata.title))"] + body)
            .joined(separator: "\n\n") + "\n"
    }

    private func frontMatter(
        transcript: TurnSegmentedTranscript,
        metadata: TranscriptMarkdownMetadata,
        exportedAt: Date,
        hasCuts: Bool
    ) -> [String] {
        var lines = ["---", "title: \(yamlString(metadata.title))"]
        if let sourceFileName = metadata.sourceFileName {
            lines.append("source_file: \(yamlString(sourceFileName))")
        }
        if let recordedAt = metadata.recordedAt {
            lines.append("recorded_at: \(yamlString(iso8601(recordedAt)))")
        }
        lines.append("exported_at: \(yamlString(iso8601(exportedAt)))")
        if let duration = metadata.duration {
            lines.append("duration_seconds: \(decimal(duration))")
        }
        lines.append(
            "language: \(yamlString(transcript.localeIdentifier.replacingOccurrences(of: "_", with: "-")))"
        )
        lines.append("speaker_count: \(transcript.speakers.count)")
        let knownSpeakers = transcript.speakers.filter { $0.knownSpeakerID != nil }
        lines.append("known_speaker_count: \(knownSpeakers.count)")
        let knownSpeakerNames = knownSpeakers.map { yamlString($0.displayName) }.joined(separator: ", ")
        lines.append("known_speakers: [\(knownSpeakerNames)]")
        let unknownSpeakerCount = transcript.speakers.count - knownSpeakers.count
        if unknownSpeakerCount > 0 {
            lines.append("unknown_speaker_count: \(unknownSpeakerCount)")
        }
        lines.append("edited: \(hasCuts)")
        if let modelRevision = transcript.transcriptionProvenance?.modelRevision {
            lines.append("model_revision: \(yamlString(modelRevision))")
        }
        lines.append("---")
        return lines
    }

    private func escapedMarkdown(_ text: String) -> String {
        let escapableCharacters = Set<Character>("\\`*_[]<>#~")
        let escaped = text.reduce(into: "") { result, character in
            if escapableCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }

        return escaped.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                if line.hasPrefix("- ") || line.hasPrefix("+ ") {
                    return "\\\(line)"
                }

                let digits = line.prefix(while: \.isNumber)
                let remainder = line.dropFirst(digits.count)
                if !digits.isEmpty, remainder.hasPrefix(". ") || remainder.hasPrefix(") ") {
                    return "\(digits)\\\(remainder)"
                }
                return String(line)
            }
            .joined(separator: "\n")
    }

    private func yamlString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
            let encoded = String(data: data, encoding: .utf8)
        else {
            preconditionFailure("Encoding a string as JSON must succeed.")
        }
        return encoded
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func decimal(_ value: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}
