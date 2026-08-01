import AVFoundation
import CoreMedia
import Foundation

extension AVAssetReaderCodecMediaSource {
    func finishVideoIfNeeded(_ reader: AVAssetReader) throws {
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

    func finishAudioIfNeeded(_ reader: AVAssetReader) throws {
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

    func reset() {
        resetVideoReader()
        resetAudioReader()
    }

    func resetVideoReader() {
        videoReader?.cancelReading()
        videoReader = nil
        videoOutput = nil
        fallbackFrameDuration = 0
    }

    func resetAudioReader() {
        audioReader?.cancelReading()
        audioReader = nil
        audioOutput = nil
    }

    func presentationTime(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        return seconds.isFinite ? max(0, seconds) : 0
    }

    func duration(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        guard seconds.isFinite, seconds > 0 else {
            return fallbackFrameDuration
        }

        return seconds
    }

    func audioDuration(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        let seconds = CMTimeGetSeconds(CMSampleBufferGetDuration(sampleBuffer))
        if seconds.isFinite, seconds > 0 {
            return seconds
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        return max(Double(sampleCount) / Double(audioSampleRate), 1 / Double(audioSampleRate))
    }

    func pcmData(from sampleBuffer: CMSampleBuffer) throws -> Data {
        try sampleBuffer.copiedPCMData(
            missingDataError: AVAssetReaderCodecMediaSourceError.missingAudioData,
            copyError: AVAssetReaderCodecMediaSourceError.audioDataCopyFailed
        )
    }

    func frameCount(duration: TimeInterval, frameRate: FrameRate) -> Int {
        max(1, Int((duration * Double(frameRate.framesPerSecond)).rounded()))
    }

    func audioChunkCount(duration: TimeInterval) -> Int {
        let chunkDuration = Double(audioFramesPerChunk) / Double(audioSampleRate)
        return max(1, Int((duration / chunkDuration).rounded(.up)))
    }
}
