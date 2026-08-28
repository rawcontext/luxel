import Foundation
import LuxelCore
import Testing

@Suite("Codec export pipeline")
struct CodecExportPipelineTests {
    @Test("pipeline writes encoded packets before finalizing")
    func pipelineWritesEncodedPacketsBeforeFinalizing() async throws {
        let events = PipelineEventLog()
        let pixelSize = try PixelSize(width: 4, height: 4)
        let mediaSource = try makeMediaSource(
            events: events,
            pixelSize: pixelSize,
            videoFrameIndices: [0, 1],
            audioChunks: [
                try CodecAudioChunk(dataString: "pcm0", presentationTime: 0, duration: 0.02)
            ]
        )
        let pipeline = CodecExportPipeline(
            mediaSource: mediaSource,
            videoEncoder: StubVideoEncoder(events: events),
            audioEncoder: StubAudioEncoder(events: events),
            muxer: StubContainerMuxer(events: events)
        )

        let exported = try await pipeline.export(
            makeRequest(shouldMute: false),
            to: URL(fileURLWithPath: "/tmp/out.webm")
        )

        #expect(exported.fileURL.path == "/tmp/out.webm")
        #expect(exported.format == .webm)
        #expect(exported.pixelSize == pixelSize)
        #expect(!exported.shouldMute)
        #expect(
            await events.snapshot() == [
                "source.prepare:webm",
                "video.prepare:4x4:30:balanced",
                "audio.prepare:48000:2:balanced",
                "muxer.begin:webm:video,audio",
                "source.video:0",
                "source.audio:0",
                "video.encode:0",
                "muxer.write:video:v0",
                "source.video:0.033",
                "audio.encode:0",
                "muxer.write:audio:a0",
                "video.encode:0.033",
                "muxer.write:video:v33",
                "video.finish",
                "audio.finish",
                "muxer.write:video:vf",
                "muxer.write:audio:af",
                "muxer.finalize"
            ])
    }
    @Test("muted requests skip audio source and encoder")
    func mutedRequestsSkipAudioSourceAndEncoder() async throws {
        let events = PipelineEventLog()
        let pixelSize = try PixelSize(width: 4, height: 4)
        let mediaSource = try makeMediaSource(
            events: events,
            pixelSize: pixelSize,
            videoFrameIndices: [0],
            audioChunks: [try CodecAudioChunk(dataString: "pcm0", presentationTime: 0, duration: 0.02)]
        )
        let pipeline = CodecExportPipeline(
            mediaSource: mediaSource,
            videoEncoder: StubVideoEncoder(events: events),
            muxer: StubContainerMuxer(events: events)
        )

        let exported = try await pipeline.export(
            makeRequest(shouldMute: true),
            to: URL(fileURLWithPath: "/tmp/out.webm")
        )
        let snapshot = await events.snapshot()

        #expect(exported.shouldMute)
        #expect(snapshot.contains("muxer.begin:webm:video"))
        #expect(!snapshot.contains { $0.hasPrefix("audio.") || $0.hasPrefix("source.audio") })
    }
    @Test("pipeline progress is monotonic")
    func pipelineProgressIsMonotonic() async throws {
        let events = PipelineEventLog()
        let progress = PipelineProgressRecorder()
        let pixelSize = try PixelSize(width: 4, height: 4)
        let mediaSource = try makeMediaSource(
            events: events,
            pixelSize: pixelSize,
            videoFrameIndices: [0, 1, 2],
            audioChunks: [
                try CodecAudioChunk(dataString: "pcm0", presentationTime: 0, duration: 0.02),
                try CodecAudioChunk(dataString: "pcm1", presentationTime: 0.02, duration: 0.02)
            ]
        )
        let pipeline = CodecExportPipeline(
            mediaSource: mediaSource,
            videoEncoder: StubVideoEncoder(events: events),
            audioEncoder: StubAudioEncoder(events: events),
            muxer: StubContainerMuxer(events: events)
        )

        _ = try await pipeline.export(
            makeRequest(shouldMute: false),
            to: URL(fileURLWithPath: "/tmp/out.webm")
        ) { value in
            await progress.append(value)
        }

        let values = await progress.values()

        #expect(values.first == 0)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
    }

    private func makeMediaSource(
        events: PipelineEventLog,
        pixelSize: PixelSize,
        videoFrameIndices: [Int],
        audioChunks: [CodecAudioChunk]
    ) throws -> StubCodecMediaSource {
        try StubCodecMediaSource(
            events: events,
            frames: videoFrameIndices.map { try makeVideoFrame(index: $0, pixelSize: pixelSize) },
            audioChunks: audioChunks
        )
    }

    @Test("cancellation cancels muxer without finalizing")
    func cancellationCancelsMuxerWithoutFinalizing() async throws {
        let events = PipelineEventLog()
        let pixelSize = try PixelSize(width: 4, height: 4)
        let mediaSource = BlockingCodecMediaSource(
            events: events,
            firstFrame: try makeVideoFrame(index: 0, pixelSize: pixelSize)
        )
        let pipeline = CodecExportPipeline(
            mediaSource: mediaSource,
            videoEncoder: StubVideoEncoder(events: events),
            muxer: StubContainerMuxer(events: events)
        )

        let task = Task {
            try await pipeline.export(
                makeRequest(shouldMute: true),
                to: URL(fileURLWithPath: "/tmp/out.webm")
            )
        }

        await events.waitFor("source.video.wait")
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let snapshot = await events.snapshot()
        #expect(snapshot.contains("muxer.cancel"))
        #expect(!snapshot.contains("muxer.finalize"))
    }

    private func makeRequest(shouldMute: Bool) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: .webm,
            pixelSize: PixelSize(width: 4, height: 4),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 1),
            shouldMute: shouldMute,
            shouldCrop: false,
            quality: .balanced
        )
    }

    private func makeVideoFrame(index: Int, pixelSize: PixelSize) throws -> CodecVideoFrame {
        try CodecVideoFrame(
            frame: I420Frame(
                pixelSize: pixelSize,
                yPlane: Data(repeating: UInt8(index), count: pixelSize.width * pixelSize.height),
                uPlane: Data(repeating: UInt8(index), count: pixelSize.width * pixelSize.height / 4),
                vPlane: Data(repeating: UInt8(index), count: pixelSize.width * pixelSize.height / 4)
            ),
            presentationTime: Double(index) / 30,
            duration: 1 / 30
        )
    }
}

actor PipelineEventLog {
    private var events: [String] = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func append(_ event: String) {
        events.append(event)
        let continuations = waiters.removeValue(forKey: event) ?? []
        for continuation in continuations {
            continuation.resume()
        }
    }

    func snapshot() -> [String] {
        events
    }

    func waitFor(_ event: String) async {
        guard !events.contains(event) else {
            return
        }

        await withCheckedContinuation { continuation in
            waiters[event, default: []].append(continuation)
        }
    }
}

private actor PipelineProgressRecorder {
    private var recordedValues: [Double] = []

    func append(_ value: Double) {
        recordedValues.append(value)
    }

    func values() -> [Double] {
        recordedValues
    }
}

private actor StubCodecMediaSource: CodecMediaSource {
    private let events: PipelineEventLog
    private var frames: [CodecVideoFrame]
    private var audioChunks: [CodecAudioChunk]
    private let initialVideoFrameCount: Int
    private let initialAudioChunkCount: Int

    init(events: PipelineEventLog, frames: [CodecVideoFrame], audioChunks: [CodecAudioChunk] = []) {
        self.events = events
        self.frames = frames
        self.audioChunks = audioChunks
        initialVideoFrameCount = frames.count
        initialAudioChunkCount = audioChunks.count
    }

    func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
        let request = input.request
        await events.append("source.prepare:\(request.format.rawValue)")
        return try CodecMediaSourceDescription(
            videoFrameCount: initialVideoFrameCount,
            audioChunkCount: initialAudioChunkCount,
            audioSampleRate: initialAudioChunkCount > 0 ? 48_000 : nil,
            audioChannelCount: initialAudioChunkCount > 0 ? 2 : nil
        )
    }

    func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard !frames.isEmpty else {
            return nil
        }

        let frame = frames.removeFirst()
        await events.append("source.video:\(frame.presentationTime.shortText)")
        return frame
    }

    func nextAudioChunk() async throws -> CodecAudioChunk? {
        guard !audioChunks.isEmpty else {
            return nil
        }

        let chunk = audioChunks.removeFirst()
        await events.append("source.audio:\(chunk.presentationTime.shortText)")
        return chunk
    }
}

private actor BlockingCodecMediaSource: CodecMediaSource {
    private let events: PipelineEventLog
    private var firstFrame: CodecVideoFrame?

    init(events: PipelineEventLog, firstFrame: CodecVideoFrame) {
        self.events = events
        self.firstFrame = firstFrame
    }

    func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
        let request = input.request
        await events.append("source.prepare:\(request.format.rawValue)")
        return try CodecMediaSourceDescription(videoFrameCount: 2)
    }

    func nextVideoFrame() async throws -> CodecVideoFrame? {
        if let frame = firstFrame {
            firstFrame = nil
            await events.append("source.video:\(frame.presentationTime.shortText)")
            return frame
        }

        await events.append("source.video.wait")
        try await Task.sleep(for: .seconds(30))
        return nil
    }

    func nextAudioChunk() async throws -> CodecAudioChunk? {
        nil
    }
}

private actor StubVideoEncoder: CodecVideoEncoder {
    private let events: PipelineEventLog

    init(events: PipelineEventLog) {
        self.events = events
    }

    func prepare(_ configuration: CodecVideoEncoderConfiguration) async throws {
        await events.append(
            "video.prepare:\(configuration.pixelSize.width)x\(configuration.pixelSize.height)"
                + ":\(configuration.frameRate.framesPerSecond):\(configuration.quality.rawValue)"
        )
    }

    func encode(frame: CodecVideoFrame) async throws -> [EncodedPacket] {
        await events.append("video.encode:\(frame.presentationTime.shortText)")
        return [
            try EncodedPacket(
                dataString: "v\(Int((frame.presentationTime * 1_000).rounded()))",
                presentationTime: frame.presentationTime,
                duration: frame.duration,
                isKeyFrame: frame.presentationTime == 0
            )
        ]
    }

    func finish() async throws -> [EncodedPacket] {
        await events.append("video.finish")
        return [
            try EncodedPacket(dataString: "vf", presentationTime: 1, duration: 0, isKeyFrame: false)
        ]
    }
}

private actor StubAudioEncoder: CodecAudioEncoder {
    private let events: PipelineEventLog

    init(events: PipelineEventLog) {
        self.events = events
    }

    func prepare(_ configuration: CodecAudioEncoderConfiguration) async throws {
        await events.append(
            "audio.prepare:\(configuration.sampleRate):\(configuration.channelCount)"
                + ":\(configuration.quality.rawValue)"
        )
    }

    func encode(chunk: CodecAudioChunk) async throws -> [EncodedPacket] {
        await events.append("audio.encode:\(chunk.presentationTime.shortText)")
        return [
            try EncodedPacket(
                dataString: "a\(Int((chunk.presentationTime * 1_000).rounded()))",
                presentationTime: chunk.presentationTime,
                duration: chunk.duration,
                isKeyFrame: true
            )
        ]
    }

    func finish() async throws -> [EncodedPacket] {
        await events.append("audio.finish")
        return [try EncodedPacket(dataString: "af", presentationTime: 1, duration: 0, isKeyFrame: true)]
    }
}
