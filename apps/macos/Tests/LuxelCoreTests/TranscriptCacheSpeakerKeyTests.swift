import Foundation
import Testing

@testable import LuxelCore

// MARK: - Cache keying

@Suite("Transcript cache speaker keying")
struct TranscriptCacheSpeakerKeyTests {
    private struct CacheFixture {
        let cache: ApplicationSupportTranscriptCache
        let audioURL: URL
        let directory: URL
    }

    private func makeCacheAndAudioFile() throws -> CacheFixture {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelTranscriptCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let audioURL = directory.appending(path: "recording.m4a")
        try Data(repeating: 0x11, count: 128).write(to: audioURL)
        return CacheFixture(
            cache: ApplicationSupportTranscriptCache(cacheDirectory: directory),
            audioURL: audioURL,
            directory: directory
        )
    }

    private func sampleTranscript() throws -> TurnSegmentedTranscript {
        let span = try TimedTranscriptSpan(id: "span-0", text: "Cached", start: 0, end: 1)
        return try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                try TranscriptTurn(
                    id: "turn-0", spanIDs: [span.id], start: 0, end: 1, text: span.text)
            ],
            localeIdentifier: "en_US"
        )
    }

    @Test("cache keys differ for diarization disabled and enabled")
    func cacheKeysDifferByDiarizationMode() throws {
        let fixture = try makeCacheAndAudioFile()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let disabledRequest = AudioTranscriptRequest(
            audioURL: fixture.audioURL,
            locale: Locale(identifier: "en_US")
        )
        let enabledRequest = disabledRequest.replacingSpeakerDiarizationMode(
            .enabled,
            modelRevision: "rev-1"
        )

        try fixture.cache.save(try sampleTranscript(), for: enabledRequest)

        #expect(try fixture.cache.load(for: disabledRequest) == nil)
        #expect(try fixture.cache.load(for: enabledRequest) != nil)
    }

    @Test("cache keys differ across model revisions and library revisions")
    func cacheKeysDifferAcrossRevisions() throws {
        let fixture = try makeCacheAndAudioFile()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let base = AudioTranscriptRequest(
            audioURL: fixture.audioURL,
            locale: Locale(identifier: "en_US")
        )
        let revisionOne = base.replacingSpeakerDiarizationMode(
            .enabled, modelRevision: "rev-1", libraryRevision: "lib-1")
        let revisionTwo = base.replacingSpeakerDiarizationMode(
            .enabled, modelRevision: "rev-2", libraryRevision: "lib-1")
        let libraryTwo = base.replacingSpeakerDiarizationMode(
            .enabled, modelRevision: "rev-1", libraryRevision: "lib-2")

        try fixture.cache.save(try sampleTranscript(), for: revisionOne)

        #expect(try fixture.cache.load(for: revisionOne) != nil)
        #expect(try fixture.cache.load(for: revisionTwo) == nil)
        #expect(try fixture.cache.load(for: libraryTwo) == nil)
    }

    @Test("cache keys differ across diarization speaker count hints")
    func cacheKeysDifferAcrossSpeakerCountHints() throws {
        let fixture = try makeCacheAndAudioFile()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let automatic = AudioTranscriptRequest(
            audioURL: fixture.audioURL,
            locale: Locale(identifier: "en_US")
        ).replacingSpeakerDiarizationMode(.enabled, modelRevision: "rev-1")
        let exact = automatic.replacingSpeakerCountHint(.exact(5))
        let range = automatic.replacingSpeakerCountHint(.range(min: 4, max: 6))

        try fixture.cache.save(try sampleTranscript(), for: exact)

        #expect(try fixture.cache.load(for: exact) != nil)
        #expect(try fixture.cache.load(for: automatic) == nil)
        #expect(try fixture.cache.load(for: range) == nil)
    }

    @Test("diarized transcripts round-trip speakers through the cache")
    func diarizedTranscriptRoundTripsSpeakers() throws {
        let fixture = try makeCacheAndAudioFile()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let span = try TimedTranscriptSpan(
            id: "span-0", text: "Hello", start: 0, end: 1, speakerID: "speaker-0")
        let transcript = try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                try TranscriptTurn(
                    id: "turn-0",
                    spanIDs: [span.id],
                    start: 0,
                    end: 1,
                    text: span.text,
                    speakerID: "speaker-0"
                )
            ],
            localeIdentifier: "en_US",
            speakers: [try TranscriptSpeakerLabel(id: "speaker-0", displayName: "Speaker 1")]
        )
        let request = AudioTranscriptRequest(
            audioURL: fixture.audioURL,
            locale: Locale(identifier: "en_US")
        ).replacingSpeakerDiarizationMode(.enabled, modelRevision: "rev-1")

        try fixture.cache.save(transcript, for: request)
        let loaded = try fixture.cache.load(for: request)

        #expect(loaded?.speakers.map(\.displayName) == ["Speaker 1"])
        #expect(loaded?.turns.first?.speakerID == "speaker-0")
    }
}
