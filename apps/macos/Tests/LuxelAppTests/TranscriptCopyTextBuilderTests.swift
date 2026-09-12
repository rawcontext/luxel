import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@Suite("Transcript copy text")
struct TranscriptCopyTextBuilderTests {
    @Test("no-cut copy preserves original turn text in Markdown")
    func noCutCopyPreservesOriginalText() throws {
        let transcript = try sampleTranscript()

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: [],
            hasCuts: false,
            metadata: metadata,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasSuffix("# Demo\n\nWait... what?\n"))
        #expect(text.contains("edited: false"))
    }

    @Test("cut copy uses only visible edited words")
    func cutCopyUsesVisibleWords() throws {
        let transcript = try sampleTranscript()
        let visible = [
            TranscriptEditableWord(
                id: "first",
                turnID: "turn",
                text: "Wait...",
                sourceRange: try TimeRange(start: 0, end: 0.5)
            )
        ]

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: visible,
            hasCuts: true,
            metadata: metadata,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasSuffix("# Demo\n\nWait...\n"))
        #expect(text.contains("edited: true"))
    }

    @Test("copy omits the audio source while preserving the speaker label")
    func copyOmitsAudioSource() throws {
        let speaker = try TranscriptSpeakerLabel(id: "speaker", displayName: "Speaker 1")
        let transcript = try sampleTranscript(source: .microphone, speaker: speaker)

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: [],
            hasCuts: false,
            metadata: metadata,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasSuffix("**Speaker 1**\n\nWait... what?\n"))
        #expect(!text.contains("Microphone"))
        #expect(text.contains("known_speakers: []"))
        #expect(text.contains("unknown_speaker_count: 1"))
    }

    @Test("timestamps can be included for original and edited transcripts", arguments: [false, true])
    func timestampsAreOptional(hasCuts: Bool) throws {
        let speaker = try TranscriptSpeakerLabel(id: "speaker", displayName: "Speaker 1")
        let transcript = try sampleTranscript(speaker: speaker)
        let words = try TranscriptWordIndex(transcript: transcript).words
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: words,
            hasCuts: hasCuts,
            metadata: metadata,
            includesTimestamps: true,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasSuffix("**Speaker 1** · `00:00`\n\nWait... what?\n"))
    }

    @Test("front matter lists known speaker names and counts anonymous speakers")
    func frontMatterSummarizesSpeakers() throws {
        let names = ["Mara O'Connor", "Jules \"JJ\" Cruz", "Noor \\ Kim"]
        let knownSpeakers = try names.enumerated().map { index, name in
            try TranscriptSpeakerLabel(id: "known-\(index)", displayName: name, knownSpeakerID: UUID())
        }
        let anonymous = try TranscriptSpeakerLabel(id: "unknown", displayName: "Speaker 4")
        let transcript = try transcriptWithSpeakers(knownSpeakers + [anonymous])
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript, visibleWords: [], hasCuts: false, metadata: metadata
        )

        #expect(text.contains("speaker_count: 4\n"))
        #expect(text.contains("known_speaker_count: 3\n"))
        #expect(text.contains("unknown_speaker_count: 1\n"))
        let namesLine = try #require(
            text.components(separatedBy: .newlines).first {
                $0.hasPrefix("known_speakers: ")
            })
        let namesJSON = Data(namesLine.dropFirst("known_speakers: ".count).utf8)
        #expect(try JSONDecoder().decode([String].self, from: namesJSON) == names)
    }

    @Test("front matter omits the unknown count when every speaker is known")
    func allKnownSpeakersOmitUnknownCount() throws {
        let speaker = try TranscriptSpeakerLabel(
            id: "known", displayName: "Mara O'Connor", knownSpeakerID: UUID()
        )
        let transcript = try sampleTranscript(speaker: speaker)
        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript, visibleWords: [], hasCuts: false, metadata: metadata
        )

        #expect(text.contains("known_speaker_count: 1\n"))
        #expect(text.contains("known_speakers: [\"Mara O'Connor\"]\n"))
        #expect(!text.contains("unknown_speaker_count:"))
    }

    @Test("copy includes structured front matter")
    func copyIncludesFrontMatter() throws {
        let transcript = try sampleTranscript(
            provenance: TranscriptionProvenance(
                engine: .parakeetTDTv3,
                modelRevision: "v3",
                configurationRevision: "balanced"
            )
        )

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: [],
            hasCuts: false,
            metadata: metadata,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasPrefix("---\ntitle: \"Demo\""))
        #expect(text.contains("source_file: \"Demo.mov\""))
        #expect(text.contains("recorded_at: \"1970-01-01T00:00:00Z\""))
        #expect(text.contains("duration_seconds: 65.500"))
        #expect(text.contains("language: \"en-US\""))
        #expect(text.contains("model_revision: \"v3\""))
        #expect(!text.contains("transcription_engine:"))
        #expect(!text.contains("configuration_revision:"))
        #expect(!text.contains("word_count:"))
        #expect(text.contains("known_speaker_count: 0"))
        #expect(text.contains("known_speakers: []"))
        #expect(!text.contains("unknown_speaker_count:"))
    }

    @Test("copy escapes transcript Markdown syntax")
    func copyEscapesTranscriptMarkdown() throws {
        let span = try TimedTranscriptSpan(
            id: "markdown",
            text: "# Heading with *emphasis*",
            start: 65,
            end: 66
        )
        let transcript = try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: [span.id],
                    start: span.start,
                    end: span.end,
                    text: span.text
                )
            ],
            localeIdentifier: "en_US"
        )

        let text = TranscriptCopyTextBuilder().text(
            transcript: transcript,
            visibleWords: [],
            hasCuts: false,
            metadata: metadata,
            exportedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(text.hasSuffix("# Demo\n\n\\# Heading with \\*emphasis\\*\n"))
    }

    private var metadata: TranscriptMarkdownMetadata {
        TranscriptMarkdownMetadata(
            title: "Demo",
            sourceFileName: "Demo.mov",
            recordedAt: Date(timeIntervalSince1970: 0),
            duration: 65.5
        )
    }

    private func transcriptWithSpeakers(_ speakers: [TranscriptSpeakerLabel]) throws -> TurnSegmentedTranscript {
        let spans = try speakers.enumerated().map { index, speaker in
            try TimedTranscriptSpan(
                id: "span-\(index)", text: "Hello.", start: Double(index), end: Double(index + 1),
                speakerID: speaker.id
            )
        }
        let turns = try spans.map { span in
            try TranscriptTurn(
                id: "turn-\(span.id)", spanIDs: [span.id], start: span.start, end: span.end,
                text: span.text, speakerID: span.speakerID
            )
        }
        return try TurnSegmentedTranscript(spans: spans, turns: turns, localeIdentifier: "en_US", speakers: speakers)
    }

    private func sampleTranscript(
        source: TranscriptSourceLabel? = nil,
        speaker: TranscriptSpeakerLabel? = nil,
        provenance: TranscriptionProvenance? = nil
    ) throws -> TurnSegmentedTranscript {
        let spans = try [
            TimedTranscriptSpan(
                id: "first",
                text: "Wait...",
                start: 0,
                end: 0.5,
                source: source,
                speakerID: speaker?.id
            ),
            TimedTranscriptSpan(
                id: "second",
                text: "what?",
                start: 0.6,
                end: 1,
                source: source,
                speakerID: speaker?.id
            )
        ]
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: spans.map(\.id),
                    start: 0,
                    end: 1,
                    text: "Wait... what?",
                    source: source,
                    speakerID: speaker?.id
                )
            ],
            localeIdentifier: "en_US",
            speakers: speaker.map { [$0] } ?? [],
            transcriptionProvenance: provenance
        )
    }
}
