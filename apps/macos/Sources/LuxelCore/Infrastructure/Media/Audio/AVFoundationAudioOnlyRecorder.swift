@preconcurrency import AVFoundation
import Foundation

public final class AVFoundationAudioOnlyRecorder: AudioRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var activeSession: AudioOnlyCaptureSession?

    public init(audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)? = nil) {
        self.audioLevelHandler = audioLevelHandler
    }

    public func startRecording(_ request: AudioRecordingRequest) async throws {
        guard request.audio.capturesMicrophone, !request.audio.capturesSystemAudio else {
            throw AVFoundationAudioOnlyRecorderError.unsupportedAudioSource
        }

        guard lock.withLock({ activeSession == nil }) else {
            throw AVFoundationAudioOnlyRecorderError.alreadyRecording
        }

        let session = try AudioOnlyCaptureSession(
            request: request,
            audioLevelHandler: audioLevelHandler
        )
        audioLevelHandler?(.silent)
        lock.withLock {
            activeSession = session
        }
        session.start()
    }

    public func stopRecording() async throws {
        let session = lock.withLock {
            let session = activeSession
            activeSession = nil
            return session
        }

        guard let session else {
            throw AVFoundationAudioOnlyRecorderError.notRecording
        }

        try await session.stop()
        audioLevelHandler?(.silent)
    }
}

public enum AVFoundationAudioOnlyRecorderError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case unsupportedAudioSource
    case writerSetupFailed(String)
    case noAudioSamples
    case finishFailed(String)
}

private final class AudioOnlyCaptureSession: @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "media.luxel.audio-only-recorder")
    private let writerDelegate: AudioWriterDelegate

    init(
        request: AudioRecordingRequest,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) throws {
        try FileManager.default.createDirectory(
            at: request.outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let writer = try AVAssetWriter(outputURL: request.outputFileURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: Self.outputSettings(for: request.format)
        )
        writerInput.expectsMediaDataInRealTime = true
        writerInput.metadata = AVFoundationAudioTrackMetadata.writerMetadata(for: .microphone)

        guard writer.canAdd(writerInput) else {
            throw AVFoundationAudioOnlyRecorderError.writerSetupFailed("Cannot add audio input")
        }
        writer.add(writerInput)
        writerDelegate = AudioWriterDelegate(
            writer: writer,
            writerInput: writerInput,
            audioLevelHandler: audioLevelHandler
        )

        guard let device = Self.captureDevice(deviceID: request.audio.microphoneDeviceID) else {
            throw AVFoundationAudioOnlyRecorderError.unsupportedAudioSource
        }

        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw AVFoundationAudioOnlyRecorderError.writerSetupFailed("Cannot configure audio session")
        }

        session.addInput(input)
        output.setSampleBufferDelegate(writerDelegate, queue: queue)
        session.addOutput(output)
    }

    func start() {
        queue.async { [self] in
            session.startRunning()
        }
    }

    func stop() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                output.setSampleBufferDelegate(nil, queue: nil)
                if session.isRunning {
                    session.stopRunning()
                }
                writerDelegate.finish(continuation)
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

    private static func outputSettings(for format: AudioRecordingFormat) -> [String: Any] {
        switch format {
        case .aac:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 256_000
            ]
        case .alac:
            [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1
            ]
        }
    }
}

private final class AudioWriterDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                                         @unchecked Sendable {
    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let writerInput: AVAssetWriterInput
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var didStartWriting = false

    init(
        writer: AVAssetWriter,
        writerInput: AVAssetWriterInput,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) {
        self.writer = writer
        self.writerInput = writerInput
        self.audioLevelHandler = audioLevelHandler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.withLock {
            if !didStartWriting {
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                didStartWriting = true
            }

            guard writerInput.isReadyForMoreMediaData else {
                return
            }

            writerInput.append(sampleBuffer)
        }

        if let sample = CMSampleBufferAudioLevelSampler.sample(from: sampleBuffer) {
            audioLevelHandler?(sample)
        }
    }

    func finish(_ continuation: CheckedContinuation<Void, any Error>) {
        let didStartWriting = lock.withLock {
            self.didStartWriting
        }

        guard didStartWriting else {
            writer.cancelWriting()
            continuation.resume(throwing: AVFoundationAudioOnlyRecorderError.noAudioSamples)
            return
        }

        writerInput.markAsFinished()
        writer.finishWriting { [self] in
            switch writer.status {
            case .completed:
                continuation.resume()
            case .failed, .cancelled:
                let message =
                    writer.error.map(String.init(describing:)) ?? String(describing: writer.status)
                continuation.resume(throwing: AVFoundationAudioOnlyRecorderError.finishFailed(message))
            case .unknown, .writing:
                continuation.resume(
                    throwing: AVFoundationAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            @unknown default:
                continuation.resume(
                    throwing: AVFoundationAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            }
        }
    }
}
