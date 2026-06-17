import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation recording segment composer")
struct RecordingSegmentComposerTests {
    @Test("composer stitches multiple mp4 segments into one output")
    func composerStitchesMultipleMP4SegmentsIntoOneOutput() async throws {
        let segmentFileURL = try fixtureURL("input.mp4")
        let outputFileURL = temporaryOutputURL()
        defer {
            try? FileManager.default.removeItem(at: outputFileURL)
        }

        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: segmentFileURL)

        try await AVFoundationRecordingSegmentComposer().compose(
            [segmentFileURL, segmentFileURL],
            to: outputFileURL
        )

        let output = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputFileURL)

        #expect(output.duration > source.duration * 1.9)
        #expect(output.duration < source.duration * 2.1)
        #expect(output.pixelSize == source.pixelSize)
        #expect(output.hasAudio == source.hasAudio)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-segments-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
