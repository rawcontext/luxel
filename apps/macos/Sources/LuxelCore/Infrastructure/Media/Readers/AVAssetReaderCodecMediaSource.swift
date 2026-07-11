import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public final class AVAssetReaderCodecMediaSource: CodecMediaSource, @unchecked Sendable {
    let converter: I420Converter
    let videoCompositionFactory: AVFoundationVideoCompositionFactory
    let audioSampleRate = 48_000
    let audioChannelCount = 2
    let audioFramesPerChunk = 1_024
    var videoReader: AVAssetReader?
    var videoOutput: AVAssetReaderVideoCompositionOutput?
    var audioReader: AVAssetReader?
    var audioOutput: AVAssetReaderAudioMixOutput?
    var fallbackFrameDuration: TimeInterval = 0

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

    public func prepare(_ input: MediaExportInput) async throws -> CodecMediaSourceDescription {
        reset()

        let request = input.request
        let outputPixelSize = try request.outputPixelSize
        let asset = AVURLAsset(url: request.inputFileURL)
        let sourceVideoTrack = try await firstVideoTrack(in: asset)
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
        let composition = AVMutableComposition()
        let sourceSegments = try request.timelineMapper.sourceSegments
        let unscaledDuration = try request.timelineMapper.unscaledOutputDuration
        let sourceCompositionTimeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: unscaledDuration, preferredTimescale: 60_000)
        )
        let outputDuration = CMTime(seconds: request.outputDuration, preferredTimescale: 60_000)
        let outputCompositionTimeRange = CMTimeRange(start: .zero, duration: outputDuration)
        let compositionVideoTrack = try addVideoTrack(
            to: composition,
            from: sourceVideoTrack,
            sourceSegments: sourceSegments
        )

        if request.speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let videoOutput = try await makeVideoOutput(
            sourceVideoTrack: sourceVideoTrack,
            compositionVideoTrack: compositionVideoTrack,
            timeRange: outputCompositionTimeRange,
            outputPixelSize: outputPixelSize,
            request: request
        )
        try startVideoReading(composition: composition, output: videoOutput, frameRate: request.frameRate)

        let includesAudio = !request.outputShouldMute
            && (input.preparedAudio != nil || !sourceAudioTracks.isEmpty)
        if includesAudio {
            try await prepareAudioReader(
                sourceAudioTracks: sourceAudioTracks,
                timing: CodecAudioTiming(
                    sourceSegments: sourceSegments,
                    sourceCompositionTimeRange: sourceCompositionTimeRange,
                    outputDuration: outputDuration,
                    speed: request.speed
                ),
                preparedAudio: input.preparedAudio
            )
        }

        return try CodecMediaSourceDescription(
            videoFrameCount: frameCount(duration: request.outputDuration, frameRate: request.frameRate),
            audioChunkCount: includesAudio ? audioChunkCount(duration: request.outputDuration) : 0,
            audioSampleRate: includesAudio ? audioSampleRate : nil,
            audioChannelCount: includesAudio ? audioChannelCount : nil
        )
    }

    public func nextVideoFrame() async throws -> CodecVideoFrame? {
        guard let videoReader, let videoOutput else {
            return nil
        }

        guard let sampleBuffer = videoOutput.copyNextSampleBuffer() else {
            try finishVideoIfNeeded(videoReader)
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
        guard let audioReader, let audioOutput else {
            return nil
        }

        guard let sampleBuffer = audioOutput.copyNextSampleBuffer() else {
            try finishAudioIfNeeded(audioReader)
            return nil
        }

        return try CodecAudioChunk(
            pcmData: pcmData(from: sampleBuffer),
            presentationTime: presentationTime(for: sampleBuffer),
            duration: audioDuration(for: sampleBuffer)
        )
    }
}

struct CodecAudioTiming {
    let sourceSegments: [SourceMediaSegment]
    let sourceCompositionTimeRange: CMTimeRange
    let outputDuration: CMTime
    let speed: PlaybackSpeed
}

struct CodecAudioSource {
    let tracks: [AVAssetTrack]
    let sourceSegments: [SourceMediaSegment]
    let retainedAsset: AVURLAsset?
}

public typealias AVAssetReaderVideoCodecMediaSource = AVAssetReaderCodecMediaSource
public typealias AVAssetReaderVideoCodecMediaSourceError = AVAssetReaderCodecMediaSourceError

public enum AVAssetReaderCodecMediaSourceError: Error, Equatable {
    case missingVideoTrack
    case cannotCreateVideoTrack
    case cannotCreateAudioTrack
    case cannotAddVideoOutput
    case cannotAddAudioOutput
    case readerStartFailed(String)
    case readFailed(String)
    case missingPixelBuffer
    case missingAudioData
    case audioDataCopyFailed(OSStatus)
}
