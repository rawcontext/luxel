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

        #expect(text.hasSuffix("# Demo\n\n`00:00`\n\nWait... what?\n"))
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

        #expect(text.hasSuffix("# Demo\n\n`00:00`\n\nWait...\n"))
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

        #expect(text.hasSuffix("**Speaker 1** · `00:00`\n\nWait... what?\n"))
        #expect(!text.contains("Microphone"))
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

        #expect(text.hasSuffix("`01:05`\n\n\\# Heading with \\*emphasis\\*\n"))
    }

    private var metadata: TranscriptMarkdownMetadata {
        TranscriptMarkdownMetadata(
            title: "Demo",
            sourceFileName: "Demo.mov",
            recordedAt: Date(timeIntervalSince1970: 0),
            duration: 65.5
        )
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
