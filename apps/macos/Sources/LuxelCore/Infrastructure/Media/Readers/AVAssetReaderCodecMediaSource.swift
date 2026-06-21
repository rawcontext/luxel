import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

public final class AVAssetReaderCodecMediaSource: CodecMediaSource, @unchecked Sendable {
    private let converter: I420Converter
    private let videoCompositionFactory: AVFoundationVideoCompositionFactory
    private let audioSampleRate = 48_000
    private let audioChannelCount = 2
    private let audioFramesPerChunk = 1_024
    private var videoReader: AVAssetReader?
    private var videoOutput: AVAssetReaderVideoCompositionOutput?
    private var audioReader: AVAssetReader?
    private var audioOutput: AVAssetReaderAudioMixOutput?
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
        let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
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
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            zoomBlocks: ZoomExportTimeMapper(
                trimRange: request.timeRange,
                speed: request.speed
            ).map(request.zoomBlocks)
        )

        guard reader.canAdd(videoOutput) else {
            throw AVAssetReaderVideoCodecMediaSourceError.cannotAddVideoOutput
        }

        reader.add(videoOutput)

        guard reader.startReading() else {
            throw AVAssetReaderVideoCodecMediaSourceError.readerStartFailed(reader.errorDescription)
        }

        videoReader = reader
        self.videoOutput = videoOutput
        fallbackFrameDuration = 1 / Double(request.frameRate.framesPerSecond)

        let includesAudio = !request.outputShouldMute && !sourceAudioTracks.isEmpty
        if includesAudio {
            try prepareAudioReader(
                sourceAudioTracks: sourceAudioTracks,
                sourceTimeRange: sourceTimeRange,
                sourceCompositionTimeRange: sourceCompositionTimeRange,
                outputDuration: outputDuration,
                speed: request.speed
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
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AVAssetReaderVideoCodecMediaSourceError.cannotCreateVideoTrack
        }

        try videoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: .zero)
        return videoTrack
    }

    private func prepareAudioReader(
        sourceAudioTracks: [AVAssetTrack],
        sourceTimeRange: CMTimeRange,
        sourceCompositionTimeRange: CMTimeRange,
        outputDuration: CMTime,
        speed: PlaybackSpeed
    ) throws {
        let composition = AVMutableComposition()
        let compositionAudioTracks = try sourceAudioTracks.map { sourceAudioTrack in
            try addAudioTrack(
                to: composition,
                from: sourceAudioTrack,
                sourceTimeRange: sourceTimeRange
            )
        }

        if speed != .normal {
            composition.scaleTimeRange(sourceCompositionTimeRange, toDuration: outputDuration)
        }

        let audioReader = try AVAssetReader(asset: composition)
        let audioOutput = AVAssetReaderAudioMixOutput(
            audioTracks: compositionAudioTracks,
            audioSettings: audioOutputSettings()
        )
        if speed != .normal {
            audioOutput.audioMix = makeAudioMix(for: compositionAudioTracks)
        }

        guard audioReader.canAdd(audioOutput) else {
            throw AVAssetReaderCodecMediaSourceError.cannotAddAudioOutput
        }

        audioReader.add(audioOutput)

        guard audioReader.startReading() else {
            throw AVAssetReaderCodecMediaSourceError.readerStartFailed(audioReader.errorDescription)
        }

        self.audioReader = audioReader
        self.audioOutput = audioOutput
    }

    private func addAudioTrack(
        to composition: AVMutableComposition,
        from sourceAudioTrack: AVAssetTrack,
        sourceTimeRange: CMTimeRange
    ) throws -> AVMutableCompositionTrack {
        guard
            let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw AVAssetReaderCodecMediaSourceError.cannotCreateAudioTrack
        }

        try audioTrack.insertTimeRange(sourceTimeRange, of: sourceAudioTrack, at: .zero)
        return audioTrack
    }

    private func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audioSampleRate,
            AVNumberOfChannelsKey: audioChannelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private func makeAudioMix(for audioTracks: [AVCompositionTrack]) -> AVAudioMix {
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { audioTrack in
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.audioTimePitchAlgorithm = .timeDomain
            return parameters
        }
        return audioMix
    }

    private func finishVideoIfNeeded(_ reader: AVAssetReader) throws {
        switch reader.status {
        case .failed:
            resetVideoReader()
            throw AVAssetReaderCodecMediaSourceError.readFailed(reader.errorDescription)
        case .cancelled:
            resetVideoReader()
            throw CancellationError()
        case .completed, .reading, .unknown:
            resetVideoReader()
        @unknown default:
            resetVideoReader()
        }
    }

    private func finishAudioIfNeeded(_ reader: AVAssetReader) throws {
        switch reader.status {
        case .failed:
            resetAudioReader()
            throw AVAssetReaderCodecMediaSourceError.readFailed(reader.errorDescription)
        case .cancelled:
            resetAudioReader()
            throw CancellationError()
        case .completed, .reading, .unknown:
            resetAudioReader()
        @unknown default:
            resetAudioReader()
        }
    }

    private func reset() {
        resetVideoReader()
        resetAudioReader()
    }

    private func resetVideoReader() {
        videoReader?.cancelReading()
        videoReader = nil
        videoOutput = nil
        fallbackFrameDuration = 0
    }

    private func resetAudioReader() {
        audioReader?.cancelReading()
        audioReader = nil
        audioOutput = nil
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

    private func audioDuration(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        if seconds.isFinite, seconds > 0 {
            return seconds
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        return max(Double(sampleCount) / Double(audioSampleRate), 1 / Double(audioSampleRate))
    }

    private func pcmData(from sampleBuffer: CMSampleBuffer) throws -> Data {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw AVAssetReaderCodecMediaSourceError.missingAudioData
        }

        let dataLength = CMBlockBufferGetDataLength(blockBuffer)
        guard dataLength > 0 else {
            throw AVAssetReaderCodecMediaSourceError.missingAudioData
        }

        var data = Data(count: dataLength)
        let status = data.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return OSStatus(paramErr)
            }

            return CMBlockBufferCopyDataBytes(
                blockBuffer,
                atOffset: 0,
                dataLength: dataLength,
                destination: baseAddress
            )
        }

        guard status == noErr else {
            throw AVAssetReaderCodecMediaSourceError.audioDataCopyFailed(status)
        }

        return data
    }

    private func frameCount(duration: TimeInterval, frameRate: FrameRate) -> Int {
        max(1, Int((duration * Double(frameRate.framesPerSecond)).rounded()))
    }

    private func audioChunkCount(duration: TimeInterval) -> Int {
        let chunkDuration = Double(audioFramesPerChunk) / Double(audioSampleRate)
        return max(1, Int((duration / chunkDuration).rounded(.up)))
    }
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

extension AVAssetReader {
    fileprivate var errorDescription: String {
        error.map(String.init(describing:)) ?? "Unknown AVAssetReader error"
    }
}
