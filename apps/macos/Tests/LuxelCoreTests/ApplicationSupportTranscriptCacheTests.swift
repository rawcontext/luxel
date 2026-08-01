import Foundation
import LuxelCore
import Testing

@Suite("Application Support transcript cache")
struct ApplicationSupportTranscriptCacheTests {
    @Test("cache round trips transcripts and keys by source context")
    func cacheRoundTripsTranscriptsAndKeysBySourceContext() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "LuxelTranscriptCacheTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceURL = directory.appending(path: "recording.m4a")
        let cacheDirectory = directory.appending(path: "Transcripts", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: sourceURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_100_000_000)],
            ofItemAtPath: sourceURL.path
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let cache = ApplicationSupportTranscriptCache(cacheDirectory: cacheDirectory)
        let microphoneRequest = AudioTranscriptRequest(
            audioURL: sourceURL,
            locale: Locale(identifier: "en_US"),
            sourceContext: TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil))
        )
        let unknownRequest = AudioTranscriptRequest(
            audioURL: sourceURL,
            locale: Locale(identifier: "en_US"),
            sourceContext: .unknown
        )
        let rawRequest = AudioTranscriptRequest(
            audioURL: sourceURL,
            locale: Locale(identifier: "en_US"),
            sourceContext: TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil)),
            turnSegmentationMode: .raw
        )
        let transcript = try sampleTranscript(source: .microphone)

        try cache.save(transcript, for: microphoneRequest)

        #expect(try cache.load(for: microphoneRequest) == transcript)
        #expect(try cache.load(for: unknownRequest) == nil)
        #expect(try cache.load(for: rawRequest) == nil)
    }

    private func sampleTranscript(source: TranscriptSourceLabel?) throws -> TurnSegmentedTranscript {
        try sampleTestTranscript(text: "Hello", source: source)
    }
}
