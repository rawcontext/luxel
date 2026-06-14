import Foundation
import LuxelCore
import Testing

@Suite("AVAssetReader video codec media source")
struct AVAssetReaderVideoCodecMediaSourceTests {
    @Test("source emits output-sized I420 frames")
    func sourceEmitsOutputSizedI420Frames() async throws {
        let mediaSource = AVAssetReaderVideoCodecMediaSource()
        let requestedPixelSize = try PixelSize(width: 321, height: 181)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)
        let request = try makeRequest(pixelSize: requestedPixelSize)

        let description = try await mediaSource.prepare(request)
        let frames = try await collectVideoFrames(from: mediaSource)

        #expect(description.videoFrameCount == 3)
        #expect(!description.hasAudio)
        #expect(frames.count == description.videoFrameCount)
        #expect(frames.allSatisfy { $0.frame.pixelSize == expectedPixelSize })
        #expect(frames.allSatisfy { $0.frame.yPlane.count == expectedPixelSize.width * expectedPixelSize.height })
        #expect(frames.allSatisfy { $0.frame.uPlane.count == expectedPixelSize.width * expectedPixelSize.height / 4 })
        #expect(frames.allSatisfy { $0.frame.vPlane.count == expectedPixelSize.width * expectedPixelSize.height / 4 })
        #expect(abs(frames[0].presentationTime - 0.0) < 0.02)
        #expect(abs(frames[1].presentationTime - 0.1) < 0.02)
        #expect(abs(frames[2].presentationTime - 0.2) < 0.02)
        #expect(frames.allSatisfy { abs($0.duration - 0.1) < 0.02 })
    }

    @Test("source exposes no audio chunks until audio reader is implemented")
    func sourceExposesNoAudioChunksUntilAudioReaderIsImplemented() async throws {
        let mediaSource = AVAssetReaderVideoCodecMediaSource()

        _ = try await mediaSource.prepare(try makeRequest(pixelSize: PixelSize(width: 320, height: 180)))

        #expect(try await mediaSource.nextAudioChunk() == nil)
    }

    private func collectVideoFrames(
        from mediaSource: AVAssetReaderVideoCodecMediaSource
    ) async throws -> [CodecVideoFrame] {
        var frames: [CodecVideoFrame] = []

        while let frame = try await mediaSource.nextVideoFrame() {
            frames.append(frame)
        }

        return frames
    }

    private func makeRequest(pixelSize: PixelSize) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .webm,
            pixelSize: pixelSize,
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: true,
            shouldCrop: true
        )
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
