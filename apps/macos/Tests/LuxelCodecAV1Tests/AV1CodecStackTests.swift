import Foundation
import LuxelCodecAV1
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("AV1 codec stack", .serialized)
struct AV1CodecStackTests {
    @Test("codec pipeline writes an AV1 MP4 file")
    func codecPipelineWritesAV1MP4File() async throws {
        let result = try await exportAV1(includeAudio: false)
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        #expect(result.exported.format == .av1)
        #expect(result.exported.pixelSize == result.pixelSize)
        #expect(result.exported.shouldMute)
        #expect(result.data.count > 200)
        #expect(result.data.contains(Data("ftyp".utf8)))
        #expect(result.data.contains(Data("av01".utf8)))
    }

    @Test("codec pipeline writes an AV1 MP4 file with AAC audio")
    func codecPipelineWritesAV1MP4FileWithAACAudio() async throws {
        let result = try await exportAV1(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        #expect(result.exported.format == .av1)
        #expect(!result.exported.shouldMute)
        #expect(result.data.contains(Data("av01".utf8)))
        #expect(result.data.contains(Data("mp4a".utf8)))
    }

    @Test("ffprobe accepts the generated AV1 MP4 when installed")
    func ffprobeAcceptsGeneratedAV1MP4() async throws {
        guard let ffprobe = executablePath(named: "ffprobe") else {
            return
        }

        let result = try await exportAV1(includeAudio: true)
        defer { try? FileManager.default.removeItem(at: result.outputURL) }

        let output = try runFFProbe(ffprobe: ffprobe, fileURL: result.outputURL)
        #expect(output.contains("\"codec_name\": \"av1\""))
        #expect(output.contains("\"codec_name\": \"aac\""))
    }

    @Test("media exporter consumes prepared audio when the source has no audio")
    func mediaExporterConsumesPreparedAudio() async throws {
        let outputURL = temporaryAV1URL()
        let prepared = try makePreparedAudioTestInput(format: .av1)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: prepared.preparedURL)
        }

        let exported = try await AV1MediaExporter().export(
            prepared.input,
            to: outputURL
        )
        let data = try Data(contentsOf: outputURL)

        #expect(!exported.shouldMute)
        #expect(data.contains(Data("av01".utf8)))
        #expect(data.contains(Data("mp4a".utf8)))
    }

    @Test("SVT encoder emits AV1 packets")
    func svtEncoderEmitsAV1Packets() async throws {
        let pixelSize = try PixelSize(width: 64, height: 64)
        let frameRate = try FrameRate(30)
        let encoder = SVTAV1VideoEncoder()
        try await encoder.prepare(
            CodecVideoEncoderConfiguration(
                pixelSize: pixelSize,
                frameRate: frameRate,
                quality: .compact
            ))

        var packets: [EncodedPacket] = []
        for index in 0..<4 {
            packets.append(contentsOf: try await encoder.encode(frame: makeVideoFrame(index, pixelSize)))
        }
        packets.append(contentsOf: try await encoder.finish())

        #expect(!packets.isEmpty)
        #expect(packets.allSatisfy { !$0.data.isEmpty })
        #expect(packets.contains { $0.isKeyFrame })
    }
}

private struct AV1ExportResult {
    let outputURL: URL
    let pixelSize: PixelSize
    let exported: ExportedMedia
    let data: Data
}

private func exportAV1(includeAudio: Bool) async throws -> AV1ExportResult {
    let outputURL = temporaryAV1URL()
    let pixelSize = try PixelSize(width: 64, height: 64)
    let pipeline = CodecExportPipeline(
        mediaSource: StubAV1MediaSource(
            pixelSize: pixelSize,
            frameCount: 8,
            audioChunkCount: includeAudio ? 3 : 0
        ),
        videoEncoder: SVTAV1VideoEncoder(),
        audioEncoder: includeAudio ? PCM16AudioPassthroughEncoder() : nil,
        muxer: AV1MP4Muxer()
    )
    let exported = try await pipeline.export(
        makeRequest(pixelSize: pixelSize, shouldMute: !includeAudio),
        to: outputURL
    )
    return try AV1ExportResult(
        outputURL: outputURL,
        pixelSize: pixelSize,
        exported: exported,
        data: Data(contentsOf: outputURL)
    )
}

private actor StubAV1MediaSource: CodecMediaSource {
    private let pixelSize: PixelSize
    private var nextFrameIndex = 0
    private let frameCount: Int
    private var nextAudioChunkIndex = 0
    private let audioChunkCount: Int

    init(pixelSize: PixelSize, frameCount: Int, audioChunkCount: Int = 0) {
        self.pixelSize = pixelSize
        self.frameCount = frameCount
        self.audioChunkCount = audioChunkCount
    }

    func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
        try CodecMediaSourceDescription(
            videoFrameCount: frameCount,
            audioChunkCount: audioChunkCount,
            audioSampleRate: audioChunkCount > 0 ? 48_000 : nil,
            audioChannelCount: audioChunkCount > 0 ? 2 : nil
        )
    }

    func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard nextFrameIndex < frameCount else {
            return nil
        }

        defer {
            nextFrameIndex += 1
        }
        return try makeVideoFrame(nextFrameIndex, pixelSize)
    }

    func nextAudioChunk() async throws -> CodecAudioChunk? {
        guard nextAudioChunkIndex < audioChunkCount else {
            return nil
        }

        defer {
            nextAudioChunkIndex += 1
        }
        let framesPerChunk = 1_024
        return try CodecAudioChunk(
            pcmData: Data(repeating: 0, count: framesPerChunk * 2 * MemoryLayout<Int16>.size),
            presentationTime: Double(nextAudioChunkIndex * framesPerChunk) / 48_000,
            duration: Double(framesPerChunk) / 48_000
        )
    }
}

private func makeRequest(pixelSize: PixelSize, shouldMute: Bool) throws -> ExportRequest {
    try ExportRequest(
        inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
        format: .av1,
        pixelSize: pixelSize,
        frameRate: FrameRate(30),
        timeRange: TimeRange(start: 0, end: 0.25),
        shouldMute: shouldMute,
        shouldCrop: false,
        quality: .compact
    )
}

private func temporaryAV1URL() -> URL {
    temporaryTestFileURL(pathExtension: "mp4")
}

private func fixtureURL(_ fileName: String) throws -> URL {
    try testFixtureURL(fileName)
}

private func executablePath(named name: String) -> String? {
    testExecutablePath(named: name)
}

private func runFFProbe(ffprobe: String, fileURL: URL) throws -> String {
    let result = try runTestFFProbe(executable: ffprobe, fileURL: fileURL)
    #expect(result.terminationStatus == 0)
    return result.output
}

private func makeVideoFrame(_ index: Int, _ pixelSize: PixelSize) throws -> CodecVideoFrame {
    let yValue = UInt8(32 + index * 16)
    return try CodecVideoFrame(
        frame: I420Frame(
            pixelSize: pixelSize,
            yPlane: Data(repeating: yValue, count: pixelSize.width * pixelSize.height),
            uPlane: Data(repeating: 128, count: pixelSize.width * pixelSize.height / 4),
            vPlane: Data(repeating: 128, count: pixelSize.width * pixelSize.height / 4)
        ),
        presentationTime: Double(index) / 30,
        duration: 1 / 30
    )
}
