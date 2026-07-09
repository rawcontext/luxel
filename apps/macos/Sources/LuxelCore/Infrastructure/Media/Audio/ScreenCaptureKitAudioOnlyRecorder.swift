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

private final class ScreenCaptureKitAudioOnlyCaptureSession: NSObject, SCStreamOutput,
                                                             @unchecked Sendable {
    private static let streamStartTimeout: Duration = .seconds(10)
    private static let streamStopTimeout: Duration = .seconds(5)

    private let sampleHandlerQueue = DispatchQueue(
        label: "media.luxel.screen-capture-kit-audio-only-recorder")
    private let stream: SCStream
    private let segment: ScreenCaptureKitAudioOnlyWriterSegment

    static func make(
        request: AudioRecordingRequest,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) async throws -> ScreenCaptureKitAudioOnlyCaptureSession {
        let contentFilter = try await defaultDisplayContentFilter()
        return try ScreenCaptureKitAudioOnlyCaptureSession(
            request: request,
            contentFilter: contentFilter,
            fileManager: .default,
            audioLevelHandler: audioLevelHandler
        )
    }

    private init(
        request: AudioRecordingRequest,
        contentFilter: SCContentFilter,
        fileManager: FileManager,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) throws {
        try fileManager.createDirectory(
            at: request.outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: request.outputFileURL)

        stream = SCStream(
            filter: contentFilter,
            configuration: ScreenCaptureKitAudioOnlyRecorder.makeStreamConfiguration(for: request),
            delegate: nil
        )
        segment = try ScreenCaptureKitAudioOnlyWriterSegment(
            request: request,
            outputFileURL: request.outputFileURL,
            fileManager: fileManager,
            audioLevelHandler: audioLevelHandler
        )
        super.init()

        try addStreamOutputs(for: request)
    }

    func start() async throws {
        try await Self.startStreamCapture(stream)
    }

    func stop() async throws {
        try await Self.stopStreamCapture(stream)
        try await segment.finish(on: sampleHandlerQueue)
    }

    func cancel() async {
        await segment.cancel(on: sampleHandlerQueue)
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        segment.append(sampleBuffer, outputType: type)
    }

    private func addStreamOutputs(for request: AudioRecordingRequest) throws {
        if request.audio.capturesSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
        }

        if request.audio.capturesMicrophone {
            try stream.addStreamOutput(
                self, type: .microphone, sampleHandlerQueue: sampleHandlerQueue)
        }
    }

    private static func defaultDisplayContentFilter() async throws -> SCContentFilter {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw ScreenCaptureKitAudioOnlyRecorderError.missingDisplay
        }

        return SCContentFilter(display: display, excludingWindows: [])
    }

    private static func startStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStartTimeout

        try await withCheckedThrowingContinuation { continuation in
            let streamHandle = ScreenCaptureKitAudioOnlyStreamHandle(stream)
            let completion = ScreenCaptureKitAudioOnlyRecorderCompletion(continuation)
            stream.startCapture { error in
                if let error {
                    _ = completion.resume(with: .failure(error))
                } else if !completion.resume(with: .success(())) {
                    streamHandle.stopCaptureIgnoringResult()
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                    let error = ScreenCaptureKitAudioOnlyRecorderError.startFailed(
                        "Timed out starting capture"
                    )
                    if completion.resume(with: .failure(error)) {
                        streamHandle.stopCaptureIgnoringResult()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private static func stopStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStopTimeout

        try await withCheckedThrowingContinuation { continuation in
            let completion = ScreenCaptureKitAudioOnlyRecorderCompletion(continuation)
            stream.stopCapture { error in
                if let error {
                    _ = completion.resume(with: .failure(error))
                } else {
                    _ = completion.resume(with: .success(()))
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                    _ = completion.resume(with: .success(()))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }
}

private final class ScreenCaptureKitAudioOnlyWriterSegment: @unchecked Sendable {
    private let outputFileURL: URL
    private let fileManager: FileManager
    private let writer: AVAssetWriter
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneAudioInput: AVAssetWriterInput?
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var audioLevelMixer: ScreenCaptureKitAudioOnlyLevelMixer
    private var didStartWriting = false
    private var pendingError: (any Error)?

    init(
        request: AudioRecordingRequest,
        outputFileURL: URL,
        fileManager: FileManager,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) throws {
        let writer = try AVAssetWriter(outputURL: outputFileURL, fileType: .m4a)
        let systemAudioInput = try Self.makeAudioInput(
            for: writer,
            enabled: request.audio.capturesSystemAudio,
            kind: .system,
            format: request.format
        )
        let microphoneAudioInput = try Self.makeAudioInput(
            for: writer,
            enabled: request.audio.capturesMicrophone,
            kind: .microphone,
            format: request.format
        )

        self.outputFileURL = outputFileURL
        self.fileManager = fileManager
        self.writer = writer
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
        self.audioLevelHandler = audioLevelHandler
        audioLevelMixer = ScreenCaptureKitAudioOnlyLevelMixer(audio: request.audio)
    }

    func append(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard pendingError == nil, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        updateAudioLevel(sampleBuffer, outputType: outputType)

        guard let input = input(for: outputType) else {
            return
        }

        if !didStartWriting {
            startWritingIfNeeded(for: sampleBuffer)
        }

        guard didStartWriting else {
            return
        }

        guard writer.status == .writing else {
            pendingError =
                writer.error
                ?? ScreenCaptureKitAudioOnlyRecorderError.finishFailed(
                    String(describing: writer.status))
            return
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        if !input.append(sampleBuffer), let error = writer.error {
            pendingError = error
        }
    }

    func finish(on queue: DispatchQueue) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                finish(continuation: continuation)
            }
        }
    }

    func cancel(on queue: DispatchQueue) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                writer.cancelWriting()
                try? fileManager.removeItem(at: outputFileURL)
                continuation.resume()
            }
        }
    }

    private func finish(
        continuation: CheckedContinuation<Void, any Error>
    ) {
        if let pendingError {
            writer.cancelWriting()
            try? fileManager.removeItem(at: outputFileURL)
            continuation.resume(throwing: pendingError)
            return
        }

        guard didStartWriting else {
            writer.cancelWriting()
            try? fileManager.removeItem(at: outputFileURL)
            continuation.resume(throwing: ScreenCaptureKitAudioOnlyRecorderError.noAudioSamples)
            return
        }

        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        let finishCompletion = ScreenCaptureKitAudioOnlyWriterFinishCompletion(
            segment: self,
            writer: writer,
            outputFileURL: outputFileURL,
            fileManager: fileManager,
            continuation: continuation
        )
        writer.finishWriting {
            finishCompletion.resume()
        }
    }

    private func startWritingIfNeeded(for sampleBuffer: CMSampleBuffer) {
        guard !didStartWriting else {
            return
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startTime.isValid, writer.startWriting() else {
            pendingError =
                writer.error
                ?? ScreenCaptureKitAudioOnlyRecorderError.startFailed("Cannot start asset writer")
            return
        }

        writer.startSession(atSourceTime: startTime)
        didStartWriting = true
    }

    private func input(for outputType: SCStreamOutputType) -> AVAssetWriterInput? {
        switch outputType {
        case .audio:
            systemAudioInput
        case .microphone:
            microphoneAudioInput
        case .screen:
            nil
        @unknown default:
            nil
        }
    }

    private func updateAudioLevel(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard let sample = CMSampleBufferAudioLevelSampler.sample(from: sampleBuffer),
              let combinedSample = audioLevelMixer.update(sample, outputType: outputType)
        else {
            return
        }

        audioLevelHandler?(combinedSample)
    }

    private static func makeAudioInput(
        for writer: AVAssetWriter,
        enabled: Bool,
        kind: AudioTrackKind,
        format: AudioRecordingFormat
    ) throws -> AVAssetWriterInput? {
        guard enabled else {
            return nil
        }

        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioOutputSettings(for: format)
        )
        input.expectsMediaDataInRealTime = true
        input.metadata = AVFoundationAudioTrackMetadata.writerMetadata(for: kind)

        guard writer.canAdd(input) else {
            throw ScreenCaptureKitAudioOnlyRecorderError.writerSetupFailed(
                "Cannot add \(kind.rawValue) audio input"
            )
        }

        writer.add(input)
        return input
    }

    private static func audioOutputSettings(for format: AudioRecordingFormat) -> [String: Any] {
        switch format {
        case .aac:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ]
        case .alac:
            [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2
            ]
        }
    }
}

private struct ScreenCaptureKitAudioOnlyLevelMixer {
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

private struct ScreenCaptureKitAudioOnlyStreamHandle: @unchecked Sendable {
    private let stream: SCStream

    init(_ stream: SCStream) {
        self.stream = stream
    }

    func stopCaptureIgnoringResult() {
        stream.stopCapture { _ in }
    }
}

private final class ScreenCaptureKitAudioOnlyRecorderCompletion: @unchecked Sendable {
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

private final class ScreenCaptureKitAudioOnlyWriterFinishCompletion: @unchecked Sendable {
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
