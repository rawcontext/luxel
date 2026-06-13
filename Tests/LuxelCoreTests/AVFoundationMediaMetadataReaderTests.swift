import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation media metadata reader")
struct AVFoundationMediaMetadataReaderTests {
    @Test("reader loads source metadata from reference fixture")
    func readerLoadsSourceMetadataFromReferenceFixture() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let source = try await reader.readSourceMedia(at: fixtureURL("input.mp4"))
        let expectedPixelSize = try PixelSize(width: 2560, height: 1440)
        let expectedFrameRate = try FrameRate(59)

        #expect(source.fileURL.lastPathComponent == "input.mp4")
        #expect(source.duration > 106)
        #expect(source.duration < 107)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(!source.hasAudio)
    }

    @Test("reader detects audio tracks")
    func readerDetectsAudioTracks() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let source = try await reader.readSourceMedia(at: fixtureURL("input@2x.mp4"))

        #expect(source.hasAudio)
    }

    @Test("probe treats readable incomplete recording as playable")
    func probeTreatsReadableIncompleteRecordingAsPlayable() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let result = await reader.inspectRecording(at: try fixtureURL("incomplete.mp4"))

        #expect(result == .playable)
    }

    @Test("probe reports corrupt recordings")
    func probeReportsCorruptRecordings() async throws {
        let reader = AVFoundationMediaMetadataReader()

        let result = await reader.inspectRecording(at: try fixtureURL("corrupt.mp4"))

        guard case .corrupt(let reason) = result else {
            Issue.record("Expected corrupt result")
            return
        }

        #expect(!reason.isEmpty)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
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
