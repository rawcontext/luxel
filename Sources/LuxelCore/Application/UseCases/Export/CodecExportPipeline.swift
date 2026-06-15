import Foundation

public struct CodecExportPipeline: Sendable {
    public typealias ProgressHandler = @Sendable (Double) async -> Void

    private let mediaSource: any CodecMediaSource
    private let videoEncoder: any CodecVideoEncoder
    private let audioEncoder: (any CodecAudioEncoder)?
    private let muxer: any CodecContainerMuxer

    public init(
        mediaSource: any CodecMediaSource,
        videoEncoder: any CodecVideoEncoder,
        audioEncoder: (any CodecAudioEncoder)? = nil,
        muxer: any CodecContainerMuxer
    ) {
        self.mediaSource = mediaSource
        self.videoEncoder = videoEncoder
        self.audioEncoder = audioEncoder
        self.muxer = muxer
    }

    public func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: ProgressHandler? = nil
    ) async throws -> ExportedMedia {
        do {
            let outputPixelSize = try request.outputPixelSize
            let sourceDescription = try await mediaSource.prepare(request)
            try Task.checkCancellation()

            try await videoEncoder.prepare(CodecVideoEncoderConfiguration(
                pixelSize: outputPixelSize,
                frameRate: request.frameRate,
                quality: request.resolvedQuality
            ))

            let includesAudio = !request.outputShouldMute && sourceDescription.hasAudio
            let audioEncoder = try await prepareAudioEncoder(
                includesAudio: includesAudio,
                sourceDescription: sourceDescription,
                quality: request.resolvedQuality
            )
            let tracks: [CodecTrack] = includesAudio ? [.video, .audio] : [.video]

            try await muxer.begin(try CodecMuxerConfiguration(
                outputFileURL: outputFileURL,
                format: request.format,
                tracks: tracks
            ))
            await progress?(0)

            let progressTracker = CodecExportProgressTracker(
                totalUnits: sourceDescription.videoFrameCount + (includesAudio ? sourceDescription.audioChunkCount : 0),
                progress: progress
            )

            try await writeVideoPackets(progressTracker: progressTracker)
            if includesAudio, let audioEncoder {
                try await writeAudioPackets(audioEncoder: audioEncoder, progressTracker: progressTracker)
            }

            try Task.checkCancellation()
            try await muxer.finalize()
            await progress?(1)

            return ExportedMedia(
                fileURL: outputFileURL,
                format: request.format,
                pixelSize: outputPixelSize,
                shouldMute: request.outputShouldMute
            )
        } catch is CancellationError {
            await muxer.cancel()
            throw CancellationError()
        } catch {
            await muxer.cancel()
            throw error
        }
    }

    private func prepareAudioEncoder(
        includesAudio: Bool,
        sourceDescription: CodecMediaSourceDescription,
        quality: ExportQuality
    ) async throws -> (any CodecAudioEncoder)? {
        guard includesAudio else {
            return nil
        }

        guard let audioEncoder else {
            throw CodecExportPipelineError.missingAudioEncoder
        }

        let configuration = try CodecAudioEncoderConfiguration(
            sampleRate: sourceDescription.audioSampleRate ?? 0,
            channelCount: sourceDescription.audioChannelCount ?? 0,
            quality: quality
        )
        try await audioEncoder.prepare(configuration)
        return audioEncoder
    }

    private func writeVideoPackets(progressTracker: CodecExportProgressTracker) async throws {
        while let frame = try await mediaSource.nextVideoFrame() {
            try Task.checkCancellation()
            let packets = try await videoEncoder.encode(frame: frame)
            for packet in packets {
                try await muxer.write(packet, to: .video)
            }
            await progressTracker.completeUnit()
        }

        for packet in try await videoEncoder.finish() {
            try await muxer.write(packet, to: .video)
        }
    }

    private func writeAudioPackets(
        audioEncoder: any CodecAudioEncoder,
        progressTracker: CodecExportProgressTracker
    ) async throws {
        while let chunk = try await mediaSource.nextAudioChunk() {
            try Task.checkCancellation()
            let packets = try await audioEncoder.encode(chunk: chunk)
            for packet in packets {
                try await muxer.write(packet, to: .audio)
            }
            await progressTracker.completeUnit()
        }

        for packet in try await audioEncoder.finish() {
            try await muxer.write(packet, to: .audio)
        }
    }
}

public enum CodecExportPipelineError: Error, Equatable {
    case missingAudioEncoder
}

private actor CodecExportProgressTracker {
    private let totalUnits: Int
    private let progress: CodecExportPipeline.ProgressHandler?
    private var completedUnits = 0

    init(totalUnits: Int, progress: CodecExportPipeline.ProgressHandler?) {
        self.totalUnits = max(1, totalUnits)
        self.progress = progress
    }

    func completeUnit() async {
        completedUnits += 1
        await progress?(min(Double(completedUnits) / Double(totalUnits), 1))
    }
}
