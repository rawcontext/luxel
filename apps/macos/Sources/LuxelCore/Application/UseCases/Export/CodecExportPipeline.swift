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

            try await videoEncoder.prepare(
                CodecVideoEncoderConfiguration(
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

            try await muxer.begin(
                try CodecMuxerConfiguration(
                    outputFileURL: outputFileURL,
                    format: request.format,
                    tracks: tracks,
                    pixelSize: outputPixelSize,
                    audioSampleRate: includesAudio ? sourceDescription.audioSampleRate : nil,
                    audioChannelCount: includesAudio ? sourceDescription.audioChannelCount : nil
                ))
            await progress?(0)

            let progressTracker = CodecExportProgressTracker(
                totalUnits: sourceDescription.videoFrameCount
                    + (includesAudio ? sourceDescription.audioChunkCount : 0),
                progress: progress
            )

            try await writeSourcePackets(
                includesAudio: includesAudio,
                audioEncoder: audioEncoder,
                progressTracker: progressTracker
            )

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

    private func writeSourcePackets(
        includesAudio: Bool,
        audioEncoder: (any CodecAudioEncoder)?,
        progressTracker: CodecExportProgressTracker
    ) async throws {
        var nextVideoFrame = try await mediaSource.nextVideoFrame()
        var nextAudioChunk = includesAudio ? try await mediaSource.nextAudioChunk() : nil

        while nextVideoFrame != nil || nextAudioChunk != nil {
            try Task.checkCancellation()

            if shouldWriteVideoFrame(nextVideoFrame, before: nextAudioChunk) {
                guard let frame = nextVideoFrame else {
                    continue
                }
                async let upcomingVideoFrame = mediaSource.nextVideoFrame()
                let packets = try await videoEncoder.encode(frame: frame)
                for packet in packets {
                    try await muxer.write(packet, to: .video)
                }
                await progressTracker.completeUnit()
                nextVideoFrame = try await upcomingVideoFrame
            } else if let chunk = nextAudioChunk, let audioEncoder {
                let packets = try await audioEncoder.encode(chunk: chunk)
                for packet in packets {
                    try await muxer.write(packet, to: .audio)
                }
                await progressTracker.completeUnit()
                nextAudioChunk = try await mediaSource.nextAudioChunk()
            }
        }

        var finalPackets = try await videoEncoder.finish().map {
            PendingEncodedPacket(packet: $0, track: .video)
        }
        if includesAudio, let audioEncoder {
            finalPackets.append(
                contentsOf: try await audioEncoder.finish().map {
                    PendingEncodedPacket(packet: $0, track: .audio)
                })
        }

        for packet in finalPackets.sortedByPresentationTime() {
            try await muxer.write(packet.packet, to: packet.track)
        }
    }

    private func shouldWriteVideoFrame(
        _ videoFrame: CodecVideoFrame?,
        before audioChunk: CodecAudioChunk?
    ) -> Bool {
        guard let videoFrame else {
            return false
        }
        guard let audioChunk else {
            return true
        }

        return videoFrame.presentationTime <= audioChunk.presentationTime
    }
}

private struct PendingEncodedPacket {
    let packet: EncodedPacket
    let track: CodecTrack

    var trackOrder: Int {
        switch track {
        case .video:
            0
        case .audio:
            1
        }
    }
}

extension [PendingEncodedPacket] {
    fileprivate func sortedByPresentationTime() -> [PendingEncodedPacket] {
        sorted { lhs, rhs in
            if lhs.packet.presentationTime == rhs.packet.presentationTime {
                return lhs.trackOrder < rhs.trackOrder
            }

            return lhs.packet.presentationTime < rhs.packet.presentationTime
        }
    }
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

public enum CodecExportPipelineError: Error, Equatable {
    case missingAudioEncoder
}
