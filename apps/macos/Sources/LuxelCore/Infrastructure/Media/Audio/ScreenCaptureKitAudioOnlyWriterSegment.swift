@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureKitAudioOnlyWriterSegment: @unchecked Sendable {
    private let outputFileURL: URL
    private let fileManager: FileManager
    private let writer: AVAssetWriter
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneAudioInput: AVAssetWriterInput?
    private let audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)?
    private var audioLevelMixer: RecordingAudioLevelMixer
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
        audioLevelMixer = RecordingAudioLevelMixer(audio: request.audio)
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
        switch (pendingError, didStartWriting) {
        case (let pendingError?, _):
            writer.cancelWriting()
            try? fileManager.removeItem(at: outputFileURL)
            continuation.resume(throwing: pendingError)
            return
        case (nil, false):
            writer.cancelWriting()
            try? fileManager.removeItem(at: outputFileURL)
            continuation.resume(throwing: ScreenCaptureKitAudioOnlyRecorderError.noAudioSamples)
            return
        case (nil, true):
            break
        }

        systemAudioInput?.markAsFinished()
        microphoneAudioInput?.markAsFinished()

        let finishCompletion = AudioOnlyWriterFinishCompletion(
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
        pendingError = ScreenCaptureKitAssetWriterSession.startIfNeeded(
            writer: writer,
            sampleBuffer: sampleBuffer,
            didStartWriting: &didStartWriting,
            fallbackError: ScreenCaptureKitAudioOnlyRecorderError.startFailed(
                "Cannot start asset writer"
            )
        )
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
        audioLevelMixer.publish(sampleBuffer, outputType: outputType, to: audioLevelHandler)
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
