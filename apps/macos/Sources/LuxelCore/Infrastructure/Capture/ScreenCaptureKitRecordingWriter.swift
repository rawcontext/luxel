@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureKitRecordingWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleHandlerQueue = DispatchQueue(label: "media.luxel.screen-capture-kit-recording-writer")

    private let fileManager: FileManager
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var segment: RecordingWriterSegment?

    init(
        fileManager: FileManager = .default,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.audioLevelHandler = audioLevelHandler
    }

    func startSegment(for request: RecordingRequest, outputFileURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                do {
                    guard segment == nil else {
                        throw ScreenCaptureKitRecorderError.resumeFailed(
                            "A recording segment is already active")
                    }

                    try fileManager.createDirectory(
                        at: outputFileURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try? fileManager.removeItem(at: outputFileURL)
                    segment = try RecordingWriterSegment(
                        request: request,
                        outputFileURL: outputFileURL,
                        audioLevelHandler: audioLevelHandler
                    )
                    audioLevelHandler?(.silent)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func finishSegment() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                guard let segment else {
                    continuation.resume(returning: nil)
                    return
                }

                self.segment = nil
                audioLevelHandler?(.silent)
                segment.finish(fileManager: fileManager, continuation: continuation)
            }
        }
    }

    func cancelCurrentSegment() async {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                segment?.cancel(fileManager: fileManager)
                segment = nil
                audioLevelHandler?(.silent)
                continuation.resume()
            }
        }
    }

    func hasStartedCurrentSegmentWriting() async -> Bool {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                continuation.resume(returning: segment?.hasStartedWriting == true)
            }
        }
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        segment?.append(sampleBuffer, outputType: type)
    }
}

final class RecordingWriterSegment: @unchecked Sendable {
    private let outputFileURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneAudioInput: AVAssetWriterInput?
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var audioLevelMixer: RecordingAudioLevelMixer
    private var didStartWriting = false
    private var pendingError: (any Error)?

    var hasStartedWriting: Bool {
        didStartWriting
    }

    init(
        request: RecordingRequest,
        outputFileURL: URL,
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    ) throws {
        let writer = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: ScreenCaptureKitRecordingVideoSettings.outputSettings(for: request)
        )
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw ScreenCaptureKitRecorderError.startFailed("Cannot add video writer input")
        }
        writer.add(videoInput)

        let systemAudioInput = try Self.makeAudioInput(
            for: writer,
            enabled: request.audio.capturesSystemAudio,
            kind: .system
        )
        let microphoneAudioInput = try Self.makeAudioInput(
            for: writer,
            enabled: request.audio.capturesMicrophone,
            kind: .microphone
        )

        self.outputFileURL = outputFileURL
        self.writer = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
        self.audioLevelHandler = audioLevelHandler
        self.audioLevelMixer = RecordingAudioLevelMixer(audio: request.audio)
    }

    func append(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard pendingError == nil, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        updateAudioLevel(sampleBuffer, outputType: outputType)

        let isCompleteScreenFrame =
            outputType == .screen && sampleBufferContainsCompleteFrame(sampleBuffer)
        if outputType == .screen, !isCompleteScreenFrame {
            return
        }

        guard let input = input(for: outputType) else {
            return
        }

        if !didStartWriting {
            guard isCompleteScreenFrame else {
                return
            }

            startWritingIfNeeded(for: sampleBuffer)
        }

        guard writer.status == .writing else {
            pendingError =
                writer.error ?? ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status))
            return
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        if !input.append(sampleBuffer), let error = writer.error {
            pendingError = error
        }
    }

    func finish(
        fileManager: FileManager,
        continuation: CheckedContinuation<URL?, any Error>
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
            continuation.resume(returning: nil)
            return
        }

        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        let finishCompletion = RecordingWriterFinishCompletion(
            segment: self,
            writer: writer,
            outputFileURL: outputFileURL,
            continuation: continuation
        )
        writer.finishWriting {
            finishCompletion.resume()
        }
    }

    func cancel(fileManager: FileManager) {
        writer.cancelWriting()
        try? fileManager.removeItem(at: outputFileURL)
    }

    private func startWritingIfNeeded(for sampleBuffer: CMSampleBuffer) {
        pendingError = ScreenCaptureKitAssetWriterSession.startIfNeeded(
            writer: writer,
            sampleBuffer: sampleBuffer,
            didStartWriting: &didStartWriting,
            fallbackError: ScreenCaptureKitRecorderError.startFailed("Cannot start asset writer")
        )
    }

    private func input(for outputType: SCStreamOutputType) -> AVAssetWriterInput? {
        switch outputType {
        case .screen:
            videoInput
        case .audio:
            systemAudioInput
        case .microphone:
            microphoneAudioInput
        @unknown default:
            nil
        }
    }

    private func updateAudioLevel(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        audioLevelMixer.publish(sampleBuffer, outputType: outputType, to: audioLevelHandler)
    }

    private func sampleBufferContainsCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        ScreenCaptureKitSampleAttachments.containsCompleteFrame(sampleBuffer)
    }

    private static func makeAudioInput(
        for writer: AVAssetWriter,
        enabled: Bool,
        kind: AudioTrackKind
    ) throws
    -> AVAssetWriterInput? {
        guard enabled else {
            return nil
        }

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings())
        input.expectsMediaDataInRealTime = true
        input.metadata = AVFoundationAudioTrackMetadata.writerMetadata(for: kind)

        guard writer.canAdd(input) else {
            throw ScreenCaptureKitRecorderError.startFailed("Cannot add audio writer input")
        }

        writer.add(input)
        return input
    }

    private static func audioOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
    }
}
