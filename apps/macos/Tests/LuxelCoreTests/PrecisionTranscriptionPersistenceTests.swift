import Foundation
import LuxelCore
import Testing

@Suite("Precision transcription persistence")
struct PrecisionTranscriptionPersistenceTests {
    @Test("caption provenance survives Codable editing and time mapping")
    func captionProvenanceSurvivesPersistenceAndEditing() throws {
        let provenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "revision",
            configurationRevision: "config"
        )
        let track = try CaptionTrack(
            cues: [
                CaptionCue(timeRange: TimeRange(start: 1, end: 2), text: "Hello")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .system,
            transcriptionProvenance: provenance
        )
        let decoded = try JSONDecoder().decode(
            CaptionTrack.self,
            from: JSONEncoder().encode(track)
        )
        let edited = try CaptionTrackEditor(track: decoded).replacingCue(
            at: 0,
            with: CaptionCue(timeRange: TimeRange(start: 1, end: 2), text: "Edited")
        )
        let mapped = try CaptionExportTimeMapper(
            trimRange: TimeRange(start: 0.5, end: 2.5)
        ).map(edited)
        #expect(mapped.transcriptionProvenance == provenance)
    }

    @Test("transcript cache separates Apple and Precision provenance")
    func transcriptCacheSeparatesEngineProvenance() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PrecisionCacheTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let audioURL = directory.appending(path: "audio.m4a")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        let cache = ApplicationSupportTranscriptCache(
            cacheDirectory: directory.appending(path: "cache"))
        let transcript = try sampleTranscript(provenance: .appleSpeech)
        let appleRequest = AudioTranscriptRequest(
            audioURL: audioURL,
            transcriptionProvenance: .appleSpeech
        )
        let precisionProvenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "revision",
            configurationRevision: "config"
        )
        let precisionRequest = AudioTranscriptRequest(
            audioURL: audioURL,
            transcriptionProvenance: precisionProvenance
        )
        try cache.save(transcript, for: appleRequest)
        try cache.save(
            sampleTranscript(provenance: precisionProvenance),
            for: precisionRequest
        )

        #expect(try cache.load(for: appleRequest)?.transcriptionProvenance == .appleSpeech)
        #expect(try cache.load(for: precisionRequest)?.transcriptionProvenance == precisionProvenance)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory.appending(path: "cache"),
            includingPropertiesForKeys: nil
        )
        #expect(files.count == 2)
    }

    @Test("schema 3 transcript cache documents are ignored")
    func schemaThreeCacheDocumentsAreIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PrecisionOldCacheTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let audioURL = directory.appending(path: "audio.m4a")
        let cacheDirectory = directory.appending(path: "cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        let cache = ApplicationSupportTranscriptCache(cacheDirectory: cacheDirectory)
        let request = AudioTranscriptRequest(audioURL: audioURL)
        try cache.save(sampleTranscript(provenance: .appleSpeech), for: request)
        let cacheFile = try #require(
            FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        var document = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any]
        )
        document["schemaVersion"] = 3
        try JSONSerialization.data(withJSONObject: document).write(to: cacheFile)

        #expect(try cache.load(for: request) == nil)
    }

    private func sampleTranscript(
        provenance: TranscriptionProvenance
    ) throws -> TurnSegmentedTranscript {
        let span = try TimedTranscriptSpan(id: "span-0", text: "Hello", start: 0, end: 1)
        return try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                TranscriptTurn(
                    id: "turn-0",
                    spanIDs: [span.id],
                    start: 0,
                    end: 1,
                    text: "Hello"
                )
            ],
            localeIdentifier: "en-US",
            transcriptionProvenance: provenance
        )
    }
}
