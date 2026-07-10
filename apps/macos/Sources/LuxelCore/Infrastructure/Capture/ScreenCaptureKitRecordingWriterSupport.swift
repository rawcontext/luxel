@preconcurrency import AVFoundation
import ScreenCaptureKit

enum ScreenCaptureKitRecordingVideoSettings {
    static func outputSettings(for request: RecordingRequest) -> [String: Any] {
        let pixelSize = (try? request.pixelSize.roundedToEvenDimensions) ?? request.pixelSize

        return [
            AVVideoCodecKey: request.videoCodec.avVideoCodecType,
            AVVideoWidthKey: pixelSize.width,
            AVVideoHeightKey: pixelSize.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey:
                    request.encoderFrameRateHint.framesPerSecond
            ]
        ]
    }
}

struct RecordingAudioLevelMixer {
    private let capturesSystemAudio: Bool
    private let capturesMicrophone: Bool
    private var systemSample = AudioLevelSample.silent
    private var microphoneSample = AudioLevelSample.silent

    init(audio: RecordingAudioMode) {
        self.capturesSystemAudio = audio.capturesSystemAudio
        self.capturesMicrophone = audio.capturesMicrophone
    }

    mutating func update(_ sample: AudioLevelSample, outputType: SCStreamOutputType)
    -> AudioLevelSample? {
        switch outputType {
        case .audio:
            guard capturesSystemAudio else {
                return nil
            }
            systemSample = sample
        case .microphone:
            guard capturesMicrophone else {
                return nil
            }
            microphoneSample = sample
        case .screen:
            return nil
        @unknown default:
            return nil
        }

        return AudioLevelSample.combined(
            [
                capturesSystemAudio ? systemSample : nil,
                capturesMicrophone ? microphoneSample : nil
            ].compactMap { $0 })
    }
}

final class RecordingWriterFinishCompletion: @unchecked Sendable {
    private let segment: RecordingWriterSegment
    private let writer: AVAssetWriter
    private let outputFileURL: URL
    private let continuation: CheckedContinuation<URL?, any Error>

    init(
        segment: RecordingWriterSegment,
        writer: AVAssetWriter,
        outputFileURL: URL,
        continuation: CheckedContinuation<URL?, any Error>
    ) {
        self.segment = segment
        self.writer = writer
        self.outputFileURL = outputFileURL
        self.continuation = continuation
    }

    func resume() {
        withExtendedLifetime(segment) {
            switch writer.status {
            case .completed:
                continuation.resume(returning: outputFileURL)
            case .failed, .cancelled:
                let error =
                    writer.error
                    ?? ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status))
                continuation.resume(throwing: error)
            case .unknown, .writing:
                continuation.resume(
                    throwing: ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status)))
            @unknown default:
                continuation.resume(
                    throwing: ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status)))
            }
        }
    }
}

extension RecordingCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264:
            .h264
        case .hevc:
            .hevc
        case .proRes422:
            .proRes422
        case .proRes4444:
            .proRes4444
        }
    }
}
