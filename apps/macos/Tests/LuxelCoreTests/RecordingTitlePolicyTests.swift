import Foundation
import LuxelCore
import Testing

@Suite("Recording titles")
struct RecordingTitlePolicyTests {
    @Test("only the first 200 chronological words reach title generation")
    func boundedTranscriptInput() throws {
        let leading = Array(repeating: "alpha", count: 120).joined(separator: " ")
        let trailing = Array(repeating: "beta", count: 80).joined(separator: " ")
        let spans = try [
            TimedTranscriptSpan(id: "later", text: trailing + " PRIVATE_AFTER_LIMIT", start: 10, end: 20),
            TimedTranscriptSpan(id: "earlier", text: leading, start: 0, end: 10)
        ]
        let transcript = try RawTranscriptTurnSegmenter().makeTestTranscript(spans: spans)
        let prefix = RecordingTitlePolicy.transcriptPrefix(transcript)
        #expect(prefix == leading + " " + trailing)
        #expect(prefix.split(separator: " ").count == 200)
        #expect(!prefix.contains("PRIVATE_AFTER_LIMIT"))
    }

    @Test("short transcripts use all actual words")
    func shortTranscript() throws {
        let transcript = try sampleTestTranscript(text: "Fix checkout validation", source: .microphone)
        #expect(RecordingTitlePolicy.transcriptPrefix(transcript) == "Fix checkout validation")
    }

    @Test("word limits apply to Japanese text without spaces")
    func japaneseWordBoundary() throws {
        let transcript = try sampleTestTranscript(
            text: String(repeating: "今日は良い天気です。", count: 100) + "PRIVATE_AFTER_LIMIT", source: nil)
        let prefix = RecordingTitlePolicy.transcriptPrefix(transcript)
        #expect(prefix.hasPrefix("今日は"))
        #expect(!prefix.contains("PRIVATE_AFTER_LIMIT"))
        #expect(prefix.count < transcript.spans[0].text.count)
    }

    @Test(
        "unsafe or prose model output is rejected",
        arguments: [
            "", "../../Documents", "A title\nAn explanation", "\"Quoted title\"", "“Quoted title”",
            "Recording.mp4", "2026-09-14 Meeting", "# Heading", "Path / title",
            "This is a long paragraph explaining everything that happened during the recording"
        ])
    func invalidModelOutput(_ output: String) {
        #expect(RecordingTitlePolicy.validatedTitle(output) == nil)
    }

    @Test("concise multilingual title components are accepted")
    func validTitles() {
        for title in ["Checkout validation bug", "注文フォームの修正", "Réunion produit", "결제 오류 수정"] {
            #expect(RecordingTitlePolicy.validatedTitle(title) == title)
        }
    }

    @Test("availability enables titles by default while an explicit choice persists")
    func settingDefaults() throws {
        #expect(RecordingTitlePolicy.isEnabled(preference: nil, availability: .available))
        #expect(!RecordingTitlePolicy.isEnabled(preference: nil, availability: .downloading))
        #expect(!RecordingTitlePolicy.isEnabled(preference: false, availability: .available))
        #expect(RecordingTitlePolicy.isEnabled(preference: true, availability: .notEnabled))
        var settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/recordings"))
        settings.automaticRecordingTitles = false
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.automaticRecordingTitles == false)
    }
}

extension RawTranscriptTurnSegmenter {
    fileprivate func makeTestTranscript(spans: [TimedTranscriptSpan]) throws -> TurnSegmentedTranscript {
        let ordered = spans.sorted { $0.start < $1.start }
        return try TurnSegmentedTranscript(
            spans: ordered,
            turns: ordered.map { span in
                try TranscriptTurn(id: span.id, spanIDs: [span.id], start: span.start, end: span.end, text: span.text)
            }, localeIdentifier: "en_US")
    }
}
