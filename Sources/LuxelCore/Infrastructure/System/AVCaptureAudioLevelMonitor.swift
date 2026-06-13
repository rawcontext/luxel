@preconcurrency import AVFoundation
import Foundation

public final class AVCaptureAudioLevelMonitor: NSObject, AudioLevelMonitor, @unchecked Sendable {
    private let lock = NSLock()
    private var activeSession: AudioLevelCaptureSession?

    public override init() {
        super.init()
    }

    public func start(deviceID: String?) -> AsyncStream<AudioLevelSample> {
        stop()

        return AsyncStream { continuation in
            do {
                let captureSession = try AudioLevelCaptureSession(
                    deviceID: deviceID,
                    continuation: continuation
                )
                lock.withLock {
                    activeSession = captureSession
                }
                continuation.onTermination = { [weak self, captureSession] _ in
                    captureSession.stop()
                    self?.clear(captureSession)
                }
                captureSession.start()
            } catch {
                continuation.yield(.silent)
                continuation.finish()
            }
        }
    }

    public func stop() {
        let session = lock.withLock {
            let session = activeSession
            activeSession = nil
            return session
        }

        session?.stop()
    }

    private func clear(_ session: AudioLevelCaptureSession) {
        lock.withLock {
            if activeSession === session {
                activeSession = nil
            }
        }
    }
}

private final class AudioLevelCaptureSession: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "media.luxel.audio-level-monitor")
    private let delegate: AudioLevelSampleBufferDelegate

    init(
        deviceID: String?,
        continuation: AsyncStream<AudioLevelSample>.Continuation
    ) throws {
        delegate = AudioLevelSampleBufferDelegate(continuation: continuation)

        guard let device = Self.captureDevice(deviceID: deviceID) else {
            throw AudioLevelCaptureSessionError.deviceUnavailable
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AudioLevelCaptureSessionError.sessionConfigurationFailed
        }

        session.addInput(input)
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.addOutput(output)
    }

    func start() {
        queue.async { [self] in
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            output.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private static func captureDevice(deviceID: String?) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        if let deviceID,
           deviceID != AudioInputDeviceID.systemDefault,
           let device = discoverySession.devices.first(where: { $0.uniqueID == deviceID }) {
            return device
        }

        return AVCaptureDevice.default(for: .audio) ?? discoverySession.devices.first
    }
}

private enum AudioLevelCaptureSessionError: Error {
    case deviceUnavailable
    case sessionConfigurationFailed
}

private final class AudioLevelSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let continuation: AsyncStream<AudioLevelSample>.Continuation

    init(continuation: AsyncStream<AudioLevelSample>.Continuation) {
        self.continuation = continuation
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let audioChannels = connection.audioChannels
        guard !audioChannels.isEmpty else {
            return
        }

        continuation.yield(
            AudioLevelSample.fromDecibels(
                averageLevels: audioChannels.map(\.averagePowerLevel),
                peakLevels: audioChannels.map(\.peakHoldLevel)
            )
        )
    }
}
