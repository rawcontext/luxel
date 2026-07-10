@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public final class ScreenCaptureKitAudioOnlyRecorder: AudioRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var activeSession: ScreenCaptureKitAudioOnlyCaptureSession?
    private var isStarting = false

    public init(audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)? = nil) {
        self.audioLevelHandler = audioLevelHandler
    }

    public func startRecording(_ request: AudioRecordingRequest) async throws {
        guard request.audio.capturesAudio else {
            throw ScreenCaptureKitAudioOnlyRecorderError.unsupportedAudioSource
        }

        guard
            lock.withLock({
                guard activeSession == nil, !isStarting else {
                    return false
                }

                isStarting = true
                return true
            })
        else {
            throw ScreenCaptureKitAudioOnlyRecorderError.alreadyRecording
        }

        do {
            let session = try await ScreenCaptureKitAudioOnlyCaptureSession.make(
                request: request,
                audioLevelHandler: audioLevelHandler
            )

            do {
                try await session.start()
            } catch {
                await session.cancel()
                throw error
            }

            audioLevelHandler?(.silent)
            lock.withLock {
                activeSession = session
                isStarting = false
            }
        } catch {
            lock.withLock {
                activeSession = nil
                isStarting = false
            }
            throw error
        }
    }

    public func stopRecording() async throws {
        let session = lock.withLock {
            let session = activeSession
            activeSession = nil
            return session
        }

        guard let session else {
            throw ScreenCaptureKitAudioOnlyRecorderError.notRecording
        }

        do {
            try await session.stop()
            audioLevelHandler?(.silent)
        } catch {
            audioLevelHandler?(.silent)
            throw error
        }
    }

    static func makeStreamConfiguration(for request: AudioRecordingRequest) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = request.audio.capturesSystemAudio
        configuration.captureMicrophone = request.audio.capturesMicrophone
        configuration.microphoneCaptureDeviceID = request.audio.microphoneDeviceID
        configuration.excludesCurrentProcessAudio = request.audio.capturesSystemAudio
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.queueDepth = 8
        return configuration
    }
}

public enum ScreenCaptureKitAudioOnlyRecorderError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case unsupportedAudioSource
    case missingDisplay
    case startFailed(String)
    case writerSetupFailed(String)
    case noAudioSamples
    case finishFailed(String)
}
