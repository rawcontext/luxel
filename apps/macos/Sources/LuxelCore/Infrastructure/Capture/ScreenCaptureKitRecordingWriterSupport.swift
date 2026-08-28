@preconcurrency import AVFoundation
import CoreMedia
import ScreenCaptureKit

enum ScreenCaptureKitAudioConfiguration {
    static func apply(_ audio: RecordingAudioMode, to configuration: SCStreamConfiguration) {
        configuration.capturesAudio = audio.capturesSystemAudio
        configuration.captureMicrophone = audio.capturesMicrophone
        configuration.microphoneCaptureDeviceID = audio.microphoneDeviceID
        configuration.excludesCurrentProcessAudio = audio.capturesSystemAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.queueDepth = 8
    }
}

enum ScreenCaptureKitAssetWriterSession {
    static func startIfNeeded(
        writer: AVAssetWriter,
        sampleBuffer: CMSampleBuffer,
        didStartWriting: inout Bool,
        fallbackError: @autoclosure () -> any Error
    ) -> (any Error)? {
        guard !didStartWriting else {
            return nil
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startTime.isValid, writer.startWriting() else {
            return writer.error ?? fallbackError()
        }
        writer.startSession(atSourceTime: startTime)
        didStartWriting = true
        return nil
    }
}

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

    mutating func publish(
        _ sampleBuffer: CMSampleBuffer,
        outputType: SCStreamOutputType,
        to handler: (@Sendable (AudioLevelSample) -> Void)?
    ) {
        guard let sample = CMSampleBufferAudioLevelSampler.sample(from: sampleBuffer),
            let combinedSample = update(sample, outputType: outputType)
        else {
            return
        }
        handler?(combinedSample)
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
