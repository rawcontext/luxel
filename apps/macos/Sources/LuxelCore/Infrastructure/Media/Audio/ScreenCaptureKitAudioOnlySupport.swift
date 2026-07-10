@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

struct ScreenCaptureKitAudioOnlyLevelMixer {
    private let capturesSystemAudio: Bool
    private let capturesMicrophone: Bool
    private var systemSample = AudioLevelSample.silent
    private var microphoneSample = AudioLevelSample.silent

    init(audio: RecordingAudioMode) {
        capturesSystemAudio = audio.capturesSystemAudio
        capturesMicrophone = audio.capturesMicrophone
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

struct ScreenCaptureKitAudioOnlyStreamHandle: @unchecked Sendable {
    private let stream: SCStream

    init(_ stream: SCStream) {
        self.stream = stream
    }

    func stopCaptureIgnoringResult() {
        stream.stopCapture { _ in }
    }
}

final class AudioOnlyRecorderCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, any Error>?

    init(_ continuation: CheckedContinuation<Void, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Void, any Error>) -> Bool {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else {
            return false
        }

        continuation.resume(with: result)
        return true
    }
}

final class AudioOnlyWriterFinishCompletion: @unchecked Sendable {
    private let segment: ScreenCaptureKitAudioOnlyWriterSegment
    private let writer: AVAssetWriter
    private let outputFileURL: URL
    private let fileManager: FileManager
    private let continuation: CheckedContinuation<Void, any Error>

    init(
        segment: ScreenCaptureKitAudioOnlyWriterSegment,
        writer: AVAssetWriter,
        outputFileURL: URL,
        fileManager: FileManager,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        self.segment = segment
        self.writer = writer
        self.outputFileURL = outputFileURL
        self.fileManager = fileManager
        self.continuation = continuation
    }

    func resume() {
        withExtendedLifetime(segment) {
            switch writer.status {
            case .completed:
                continuation.resume()
            case .failed, .cancelled:
                try? fileManager.removeItem(at: outputFileURL)
                let message =
                    writer.error.map(String.init(describing:)) ?? String(describing: writer.status)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(message)
                )
            case .unknown, .writing:
                try? fileManager.removeItem(at: outputFileURL)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            @unknown default:
                try? fileManager.removeItem(at: outputFileURL)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            }
        }
    }
}
