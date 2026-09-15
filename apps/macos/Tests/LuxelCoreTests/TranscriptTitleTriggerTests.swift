import Foundation
import Testing

@testable import LuxelCore

@Suite("Streaming recording titles")
struct TranscriptTitleTriggerTests {
    @Test("200 finalized words trigger immediately before transcription completes, exactly once")
    func triggersAtThreshold() throws {
        let output = TitlePrefixSpy()
        let trigger = TranscriptTitleTrigger(trackIDs: [nil], localeIdentifier: "en_US", onReady: output.append)
        trigger.receive(trackID: nil, spans: try spans(count: 199), completed: false)
        #expect(output.values.isEmpty)
        trigger.receive(trackID: nil, spans: try spans(count: 200), completed: false)
        #expect(output.values.count == 1)
        #expect(output.values[0].split(separator: " ").count == 200)
        trigger.receive(trackID: nil, spans: try spans(count: 250), completed: false)
        trigger.receive(trackID: nil, spans: try spans(count: 300), completed: true)
        #expect(output.values.count == 1)
    }

    @Test("short recordings trigger immediately when transcription finishes")
    func triggersAtShortCompletion() throws {
        let output = TitlePrefixSpy()
        let trigger = TranscriptTitleTrigger(trackIDs: [nil], localeIdentifier: "en_US", onReady: output.append)
        trigger.receive(trackID: nil, spans: try spans(count: 12), completed: false)
        #expect(output.values.isEmpty)
        trigger.receive(trackID: nil, spans: try spans(count: 12), completed: true)
        #expect(output.values.first?.split(separator: " ").count == 12)
    }

    @Test("multiple audio tracks contribute their first chronological words")
    func mergesChronologicalTracks() throws {
        let output = TitlePrefixSpy()
        let trigger = TranscriptTitleTrigger(trackIDs: [0, 1], localeIdentifier: "en_US", onReady: output.append)
        trigger.receive(trackID: 0, spans: try spans(count: 200, stride: 2, text: "alpha"), completed: false)
        #expect(output.values.isEmpty)
        trigger.receive(trackID: 1, spans: try spans(count: 99, stride: 2, offset: 1, text: "beta"), completed: false)
        #expect(output.values.isEmpty)
        trigger.receive(trackID: 1, spans: try spans(count: 100, stride: 2, offset: 1, text: "beta"), completed: false)
        #expect(output.values == [Array(repeating: "alpha beta", count: 100).joined(separator: " ")])
    }

    @Test("transcription can keep reading and save its result after the source is renamed")
    func activeTranscriptionSurvivesRename() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let lease = try TranscriptionSourceLease(sourceURL: fixture.sourceURL, temporaryDirectory: fixture.root)
        defer { lease.release() }
        let request = AudioTranscriptRequest(audioURL: fixture.sourceURL)
        let renamed = try RecordingDocumentStore().applyingAutomaticTitle("Early title", to: recording)
        #expect(try Data(contentsOf: lease.url) == Data([1, 2, 3]))
        let transcript = try sampleTestTranscript(text: "The completed transcript", source: nil)
        try fixture.cache.save(transcript, for: request)
        #expect(try fixture.cache.load(for: AudioTranscriptRequest(audioURL: renamed.primaryMediaURL)) == transcript)
        let markdown = renamed.primaryMediaURL.deletingPathExtension().appendingPathExtension("md")
        #expect(try String(contentsOf: markdown, encoding: .utf8).contains("The completed transcript"))
        lease.release()
        #expect(FileManager.default.fileExists(atPath: renamed.primaryMediaURL.path))
    }

    private func spans(count: Int, stride: Int = 1, offset: Int = 0, text: String = "word") throws
        -> [TimedTranscriptSpan] {
        try (0..<count).map {
            let start = Double($0 * stride + offset)
            return try TimedTranscriptSpan(id: "span-\($0)", text: text, start: start, end: start + 0.5)
        }
    }
}

private final class TitlePrefixSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var prefixes: [String] = []
    var values: [String] { lock.withLock { prefixes } }
    func append(_ value: String) { lock.withLock { prefixes.append(value) } }
}
