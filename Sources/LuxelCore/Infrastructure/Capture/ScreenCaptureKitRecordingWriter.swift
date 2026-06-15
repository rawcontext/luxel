@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ScreenCaptureKitRecordingWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let sampleHandlerQueue = DispatchQueue(label: "media.luxel.screen-capture-kit-recording-writer")

    private let fileManager: FileManager
    private var segment: RecordingWriterSegment?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func startSegment(for request: RecordingRequest, outputFileURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                do {
                    guard segment == nil else {
                        throw ScreenCaptureKitRecorderError.resumeFailed("A recording segment is already active")
                    }

                    try? fileManager.removeItem(at: outputFileURL)
                    segment = try RecordingWriterSegment(
                        request: request,
                        outputFileURL: outputFileURL
                    )
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
                segment.finish(fileManager: fileManager, continuation: continuation)
            }
        }
    }

    func cancelCurrentSegment() async {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                segment?.cancel(fileManager: fileManager)
                segment = nil
                continuation.resume()
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        segment?.append(sampleBuffer, outputType: type)
    }
}

private final class RecordingWriterSegment: @unchecked Sendable {
    private let outputFileURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneAudioInput: AVAssetWriterInput?
    private var didStartWriting = false
    private var pendingError: (any Error)?

    init(request: RecordingRequest, outputFileURL: URL) throws {
        let writer = try AVAssetWriter(outputURL: outputFileURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: Self.videoOutputSettings(for: request)
        )
        videoInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput) else {
            throw ScreenCaptureKitRecorderError.startFailed("Cannot add video writer input")
        }
        writer.add(videoInput)

        let systemAudioInput = try Self.makeAudioInput(for: writer, enabled: request.audio.capturesSystemAudio)
        let microphoneAudioInput = try Self.makeAudioInput(for: writer, enabled: request.audio.capturesMicrophone)

        self.outputFileURL = outputFileURL
        self.writer = writer
        self.videoInput = videoInput
        self.systemAudioInput = systemAudioInput
        self.microphoneAudioInput = microphoneAudioInput
    }

    func append(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard pendingError == nil, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if outputType == .screen, !sampleBufferContainsCompleteFrame(sampleBuffer) {
            return
        }

        guard let input = input(for: outputType), input.isReadyForMoreMediaData else {
            return
        }

        startWritingIfNeeded(for: sampleBuffer)

        guard writer.status == .writing else {
            pendingError = writer.error ?? ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status))
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
        guard !didStartWriting else {
            return
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startTime.isValid, writer.startWriting() else {
            pendingError = writer.error ?? ScreenCaptureKitRecorderError.startFailed("Cannot start asset writer")
            return
        }

        writer.startSession(atSourceTime: startTime)
        didStartWriting = true
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

    private func sampleBufferContainsCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[SCStreamFrameInfo: Any]],
            let attachments = attachmentsArray.first,
            let statusRawValue = attachments[.status] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue)
        else {
            return false
        }

        return status == .complete
    }

    private static func makeAudioInput(for writer: AVAssetWriter, enabled: Bool) throws -> AVAssetWriterInput? {
        guard enabled else {
            return nil
        }

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioOutputSettings())
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw ScreenCaptureKitRecorderError.startFailed("Cannot add audio writer input")
        }

        writer.add(input)
        return input
    }

    private static func videoOutputSettings(for request: RecordingRequest) -> [String: Any] {
        [
            AVVideoCodecKey: request.videoCodec.avVideoCodecType,
            AVVideoWidthKey: request.pixelSize.width,
            AVVideoHeightKey: request.pixelSize.height
        ]
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

private final class RecordingWriterFinishCompletion: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let outputFileURL: URL
    private let continuation: CheckedContinuation<URL?, any Error>

    init(
        writer: AVAssetWriter,
        outputFileURL: URL,
        continuation: CheckedContinuation<URL?, any Error>
    ) {
        self.writer = writer
        self.outputFileURL = outputFileURL
        self.continuation = continuation
    }

    func resume() {
        switch writer.status {
        case .completed:
            continuation.resume(returning: outputFileURL)
        case .failed, .cancelled:
            let error = writer.error ?? ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status))
            continuation.resume(throwing: error)
        case .unknown, .writing:
            continuation.resume(throwing: ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status)))
        @unknown default:
            continuation.resume(throwing: ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status)))
        }
    }
}

private extension RecordingCodec {
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
