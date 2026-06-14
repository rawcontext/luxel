import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public final class AVAssetReaderVideoCodecMediaSource: CodecMediaSource, @unchecked Sendable {
    private let converter: I420Converter
    private let videoCompositionFactory: AVFoundationVideoCompositionFactory
    private var reader: AVAssetReader?
    private var videoOutput: AVAssetReaderVideoCompositionOutput?
    private var fallbackFrameDuration: TimeInterval = 0

    public convenience init(converter: I420Converter = I420Converter()) {
        self.init(
            converter: converter,
            videoCompositionFactory: AVFoundationVideoCompositionFactory()
        )
    }

    init(
        converter: I420Converter,
        videoCompositionFactory: AVFoundationVideoCompositionFactory
    ) {
        self.converter = converter
        self.videoCompositionFactory = videoCompositionFactory
    }

    public func prepare(_ request: ExportRequest) async throws -> CodecMediaSourceDescription {
        reset()

        let outputPixelSize = try request.outputPixelSize
        let asset = AVURLAsset(url: request.inputFileURL)
        let sourceVideoTrack = try await firstVideoTrack(in: asset)
        let composition = AVMutableComposition()
        let sourceTimeRange = CMTimeRange(
            start: CMTime(seconds: request.timeRange.start, preferredTimescale: 600),
            duration: CMTime(seconds: request.timeRange.duration, preferredTimescale: 600)
        )
        let sourceCompositionTimeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let outputCompositionTimeRange = CMTimeRange(start: .zero, duration: outputDuration)
        let compositionVideoTrack = try addVideoTrack(
            to: composition,
            from: sourceVideoTrack,
            sourceTimeRange: sourceTimeRange
        )

        if request.speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let reader = try AVAssetReader(asset: composition)
        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [compositionVideoTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
            ]
        )
        videoOutput.videoComposition = try await videoCompositionFactory.makeVideoComposition(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: outputCompositionTimeRange,
            outputPixelSize: outputPixelSize,
            frameRate: request.frameRate,
            shouldCrop: request.shouldCrop
        )

        guard reader.canAdd(videoOutput) else {
            throw AVAssetReaderVideoCodecMediaSourceError.cannotAddVideoOutput
        }

        reader.add(videoOutput)

        guard reader.startReading() else {
            throw AVAssetReaderVideoCodecMediaSourceError.readerStartFailed(reader.errorDescription)
        }

        self.reader = reader
        self.videoOutput = videoOutput
        fallbackFrameDuration = 1 / Double(request.frameRate.framesPerSecond)

        return try CodecMediaSourceDescription(
            videoFrameCount: frameCount(duration: request.outputDuration, frameRate: request.frameRate)
        )
    }

    public func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard let reader, let videoOutput else {
            return nil
        }

        guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
            try finishIfNeeded(reader)
            return nil
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw AVAssetReaderVideoCodecMediaSourceError.missingPixelBuffer
        }

        return try CodecVideoFrame(
            frame: converter.convertBGRA(pixelBuffer: pixelBuffer),
            presentationTime: presentationTime(for: sampleBuffer),
            duration: duration(for: sampleBuffer)
        )
    }

    public func nextAudioChunk() async throws -> CodecAudioChunk? {
        nil
    }

    private func firstVideoTrack(in asset: AVURLAsset) async throws -> AVAssetTrack {
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw AVAssetReaderVideoCodecMediaSourceError.missingVideoTrack
        }

        return videoTrack
    }

    private func addVideoTrack(
        to composition: AVMutableComposition,
        from sourceVideoTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange
    ) throws -> AVMutableCompositionTrack {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AVAssetReaderVideoCodecMediaSourceError.cannotCreateVideoTrack
        }

        try videoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)
        return videoTrack
    }

    private func finishIfNeeded(_ reader: AVAssetReader) throws {
        switch reader.status {
        case .failed:
            reset()
            throw AVAssetReaderVideoCodecMediaSourceError.readFailed(reader.errorDescription)
        case .cancelled:
            reset()
            throw CancellationError()
        case .completed, .reading, .unknown:
            reset()
        @unknown default:
            reset()
        }
    }

    private func reset() {
        reader?.cancelReading()
        reader = nil
        videoOutput = nil
        fallbackFrameDuration = 0
    }

    private func presentationTime(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func duration(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        guard seconds.isFinite, seconds > 0 else {
            return fallbackFrameDuration
        }

        return seconds
    }

    private func frameCount(duration: TimeInterval, frameRate: FrameRate) -> Int {
        max(1, Int((duration * Double(frameRate.framesPerSecond)).rounded()))
    }
}

public enum AVAssetReaderVideoCodecMediaSourceError: Error, Equatable {
    case missingVideoTrack
    case cannotCreateVideoTrack
    case cannotAddVideoOutput
    case readerStartFailed(String)
    case readFailed(String)
    case missingPixelBuffer
}

private extension AVAssetReader {
    var errorDescription: String {
        error.map(String.init(describing:)) ?? "Unknown AVAssetReader error"
    }
}
