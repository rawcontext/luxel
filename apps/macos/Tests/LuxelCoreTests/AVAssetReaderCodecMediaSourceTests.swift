import AVFAudio
import AudioToolbox
import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("AVAssetReader codec media source", .serialized)
struct AVAssetReaderCodecMediaSourceTests {
    @Test("source emits output-sized I420 frames")
    func sourceEmitsOutputSizedI420Frames() async throws {
        let mediaSource = AVAssetReaderCodecMediaSource()
        let requestedPixelSize = try PixelSize(width: 321, height: 181)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)
        let request = try makeRequest(
            fileName: "input.mp4", pixelSize: requestedPixelSize, shouldMute: true)

        let description = try await mediaSource.prepare(request)
        let frames = try await collectVideoFrames(from: mediaSource)

        #expect(description.videoFrameCount == 3)
        #expect(!description.hasAudio)
        #expect(frames.count == description.videoFrameCount)
        #expect(frames.allSatisfy { $0.frame.pixelSize == expectedPixelSize })
        #expect(
            frames.allSatisfy {
                $0.frame.yPlane.count == expectedPixelSize.width * expectedPixelSize.height
            })
        #expect(
            frames.allSatisfy {
                $0.frame.uPlane.count == expectedPixelSize.width * expectedPixelSize.height / 4
            })
        #expect(
            frames.allSatisfy {
                $0.frame.vPlane.count == expectedPixelSize.width * expectedPixelSize.height / 4
            })
        #expect(abs(frames[0].presentationTime - 0.0) < 0.02)
        #expect(abs(frames[1].presentationTime - 0.1) < 0.02)
        #expect(abs(frames[2].presentationTime - 0.2) < 0.02)
        #expect(frames.allSatisfy { abs($0.duration - 0.1) < 0.02 })
    }

    @Test("source emits forty eight kilohertz stereo PCM chunks")
    func sourceEmitsFortyEightKilohertzStereoPCMChunks() async throws {
        let mediaSource = AVAssetReaderCodecMediaSource()
        let request = try makeRequest(
            fileName: "input@2x.mp4", pixelSize: PixelSize(width: 320, height: 180))

        let description = try await mediaSource.prepare(request)
        _ = try await collectVideoFrames(from: mediaSource)
        let chunks = try await collectAudioChunks(from: mediaSource)

        #expect(description.hasAudio)
        #expect(description.audioChunkCount > 0)
        #expect(description.audioSampleRate == 48_000)
        #expect(description.audioChannelCount == 2)
        #expect(!chunks.isEmpty)
        #expect(chunks.allSatisfy { !$0.pcmData.isEmpty })
        #expect(chunks.allSatisfy { $0.pcmData.count.isMultiple(of: 4) })
        #expect(abs(chunks[0].presentationTime - 0.0) < 0.03)
        #expect(chunks.allSatisfy { $0.duration > 0 })
        #expect(
            zip(chunks, chunks.dropFirst()).allSatisfy { $0.presentationTime <= $1.presentationTime })
    }

    @Test("muted requests skip audio sourcing")
    func mutedRequestsSkipAudioSourcing() async throws {
        let mediaSource = AVAssetReaderCodecMediaSource()

        let description = try await mediaSource.prepare(
            try makeRequest(
                fileName: "input@2x.mp4",
                pixelSize: PixelSize(width: 320, height: 180),
                shouldMute: true
            ))

        #expect(!description.hasAudio)
        #expect(try await mediaSource.nextAudioChunk() == nil)
    }

    @Test("source stitches kept video and audio segments")
    func sourceAppliesTimelineCuts() async throws {
        let mediaSource = AVAssetReaderCodecMediaSource()
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .webm,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            shouldCrop: true,
            editPlan: TimelineEditPlan(cuts: [
                TimelineCut(
                    id: "middle",
                    sourceRange: TimeRange(start: 1.1, end: 1.2),
                    kind: .transcriptSentence
                )
            ])
        )

        let description = try await mediaSource.prepare(request)
        let frames = try await collectVideoFrames(from: mediaSource)
        let chunks = try await collectAudioChunks(from: mediaSource)

        #expect(description.videoFrameCount == 2)
        #expect(frames.count == 2)
        #expect(!chunks.isEmpty)
        #expect(abs(frames[0].presentationTime) < 0.02)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.presentationTime < $1.presentationTime })
        #expect(zip(chunks, chunks.dropFirst()).allSatisfy { $0.presentationTime <= $1.presentationTime })
    }

    @Test("source reads full zero-based prepared PCM instead of original audio")
    func sourceReadsPreparedAudio() async throws {
        let preparedURL = FileManager.default.temporaryDirectory
            .appending(path: "codec-prepared-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: preparedURL) }
        try writeSilentPCM(to: preparedURL, duration: 0.3)
        let request = try makeRequest(
            fileName: "input@2x.mp4",
            pixelSize: PixelSize(width: 320, height: 180)
        )
        let mediaSource = AVAssetReaderCodecMediaSource()

        let description = try await mediaSource.prepare(
            MediaExportInput(
                request: request,
                preparedAudio: PreparedAudioAsset(
                    fileURL: preparedURL,
                    duration: 0.3,
                    sampleRate: 48_000,
                    channelCount: 2
                )
            )
        )
        _ = try await collectVideoFrames(from: mediaSource)
        let chunks = try await collectAudioChunks(from: mediaSource)

        #expect(description.hasAudio)
        #expect(!chunks.isEmpty)
        #expect(chunks[0].presentationTime == 0)
        #expect(chunks.flatMap { $0.pcmData }.allSatisfy { $0 == 0 })
    }

    private func collectVideoFrames(
        from mediaSource: AVAssetReaderCodecMediaSource
    ) async throws -> [CodecVideoFrame] {
        var frames: [CodecVideoFrame] = []

        while let frame = try await mediaSource.nextVideoFrame() {
            frames.append(frame)
        }

        return frames
    }

    private func collectAudioChunks(
        from mediaSource: AVAssetReaderCodecMediaSource
    ) async throws -> [CodecAudioChunk] {
        var chunks: [CodecAudioChunk] = []

        while let chunk = try await mediaSource.nextAudioChunk() {
            chunks.append(chunk)
        }

        return chunks
    }

    private func makeRequest(
        fileName: String,
        pixelSize: PixelSize,
        shouldMute: Bool = false
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL(fileName),
            format: .webm,
            pixelSize: pixelSize,
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: shouldMute,
            shouldCrop: true
        )
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    private func writeSilentPCM(to url: URL, duration: TimeInterval) throws {
        try writeSilentTestPCM(to: url, duration: duration)
    }

    private func packageRootURL() throws -> URL {
        try sharedPackageRootURL()
    }
}
