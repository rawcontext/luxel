import AVFAudio
import AudioToolbox
import Foundation
import LuxelCodecAV1
import LuxelCore
import Testing

@Suite("AV1 codec stack", .serialized)
struct AV1CodecStackTests {
    @Test("codec pipeline writes an AV1 MP4 file")
    func codecPipelineWritesAV1MP4File() async throws {
        let outputURL = temporaryAV1URL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = CodecExportPipeline(
            mediaSource: StubAV1MediaSource(pixelSize: pixelSize, frameCount: 8),
            videoEncoder: SVTAV1VideoEncoder(),
            muxer: AV1MP4Muxer()
        )

        let exported = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: true),
            to: outputURL
        )
        let data = try Data(contentsOf: outputURL)

        #expect(exported.format == .av1)
        #expect(exported.pixelSize == pixelSize)
        #expect(exported.shouldMute)
        #expect(data.count > 200)
        #expect(data.contains(Data("ftyp".utf8)))
        #expect(data.contains(Data("av01".utf8)))
    }

    @Test("codec pipeline writes an AV1 MP4 file with AAC audio")
    func codecPipelineWritesAV1MP4FileWithAACAudio() async throws {
        let outputURL = temporaryAV1URL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = CodecExportPipeline(
            mediaSource: StubAV1MediaSource(pixelSize: pixelSize, frameCount: 8, audioChunkCount: 3),
            videoEncoder: SVTAV1VideoEncoder(),
            audioEncoder: PCM16AudioPassthroughEncoder(),
            muxer: AV1MP4Muxer()
        )

        let exported = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: false),
            to: outputURL
        )
        let data = try Data(contentsOf: outputURL)

        #expect(exported.format == .av1)
        #expect(!exported.shouldMute)
        #expect(data.contains(Data("av01".utf8)))
        #expect(data.contains(Data("mp4a".utf8)))
    }

    @Test("ffprobe accepts the generated AV1 MP4 when installed")
    func ffprobeAcceptsGeneratedAV1MP4() async throws {
        guard let ffprobe = executablePath(named: "ffprobe") else {
            return
        }

        let outputURL = temporaryAV1URL()
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let pixelSize = try PixelSize(width: 64, height: 64)
        let pipeline = CodecExportPipeline(
            mediaSource: StubAV1MediaSource(pixelSize: pixelSize, frameCount: 8, audioChunkCount: 3),
            videoEncoder: SVTAV1VideoEncoder(),
            audioEncoder: PCM16AudioPassthroughEncoder(),
            muxer: AV1MP4Muxer()
        )

        _ = try await pipeline.export(
            makeRequest(pixelSize: pixelSize, shouldMute: false),
            to: outputURL
        )

        let output = try runFFProbe(ffprobe: ffprobe, fileURL: outputURL)
        #expect(output.contains("\"codec_name\": \"av1\""))
        #expect(output.contains("\"codec_name\": \"aac\""))
    }

    @Test("media exporter consumes prepared audio when the source has no audio")
    func mediaExporterConsumesPreparedAudio() async throws {
        let outputURL = temporaryAV1URL()
        let preparedURL = FileManager.default.temporaryDirectory
            .appending(path: "av1-prepared-\(UUID().uuidString).caf")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: preparedURL)
        }
        try writeSilentPreparedPCM(to: preparedURL, duration: 0.3)
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .av1,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            studioVoiceEnabled: true,
            shouldCrop: false,
            quality: .compact
        )

        let exported = try await AV1MediaExporter().export(
            MediaExportInput(
                request: request,
                preparedAudio: PreparedAudioAsset(
                    fileURL: preparedURL,
                    duration: 0.3,
                    sampleRate: 48_000,
                    channelCount: 2
                )
            ),
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
    FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appendingPathExtension("mp4")
}

private func fixtureURL(_ fileName: String) throws -> URL {
    try packageRootURL()
        .appending(path: "Tests/Fixtures")
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

private func writeSilentPreparedPCM(to url: URL, duration: TimeInterval) throws {
    let format = try #require(
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 2,
            interleaved: false
        )
    )
    let frameCount = AVAudioFrameCount(duration * 48_000)
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    )
    buffer.frameLength = frameCount
    let file = try AVAudioFile(
        forWriting: url,
        settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true
        ],
        commonFormat: .pcmFormatFloat32,
        interleaved: false
    )
    try file.write(from: buffer)
}

private func executablePath(named name: String) -> String? {
    let fileSystem = FileManager.default
    let searchPaths =
        (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin"]

    return
        searchPaths
        .map { URL(fileURLWithPath: $0).appending(path: name).path }
        .first { fileSystem.isExecutableFile(atPath: $0) }
}

private func runFFProbe(ffprobe: String, fileURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffprobe)
    process.arguments = [
        "-v", "error",
        "-show_format",
        "-show_streams",
        "-of", "json",
        fileURL.path
    ]

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: outputData, encoding: .utf8) ?? ""
    _ = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    #expect(process.terminationStatus == 0)
    return output
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
