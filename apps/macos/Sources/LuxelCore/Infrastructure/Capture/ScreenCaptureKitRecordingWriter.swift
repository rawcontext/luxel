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
                        throw ScreenCaptureKitRecorderError.resumeFailed("A recording segment is already active")
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
        self.audioLevelHandler = audioLevelHandler
        self.audioLevelMixer = RecordingAudioLevelMixer(audio: request.audio)
    }

    func append(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard pendingError == nil, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        updateAudioLevel(sampleBuffer, outputType: outputType)

        let isCompleteScreenFrame = outputType == .screen && sampleBufferContainsCompleteFrame(sampleBuffer)
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
            pendingError = writer.error ?? ScreenCaptureKitRecorderError.stopFailed(String(describing: writer.status))
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

    private func updateAudioLevel(_ sampleBuffer: CMSampleBuffer, outputType: SCStreamOutputType) {
        guard let sample = CMSampleBufferAudioLevelSampler.sample(from: sampleBuffer),
              let combinedSample = audioLevelMixer.update(sample, outputType: outputType) else {
            return
        }

        audioLevelHandler?(combinedSample)
    }

    private func sampleBufferContainsCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = firstSampleAttachments(from: sampleBuffer),
            let statusRawValue = frameStatusRawValue(from: attachments),
            let status = SCFrameStatus(rawValue: statusRawValue)
        else {
            return false
        }

        return status == .complete
    }

    private func firstSampleAttachments(from sampleBuffer: CMSampleBuffer) -> [AnyHashable: Any]? {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) else {
            return nil
        }

        if let typedAttachments = attachmentsArray as? [[AnyHashable: Any]],
           let attachments = typedAttachments.first {
            return attachments
        }

        let firstAttachment = (attachmentsArray as NSArray).firstObject
        if let attachments = firstAttachment as? [SCStreamFrameInfo: Any] {
            return Dictionary(uniqueKeysWithValues: attachments.map { (AnyHashable($0.key), $0.value) })
        }

        if let attachments = firstAttachment as? [AnyHashable: Any] {
            return attachments
        }

        guard let attachments = firstAttachment as? NSDictionary else {
            return nil
        }

        var result: [AnyHashable: Any] = [:]
        for (key, value) in attachments {
            if let key = key as? SCStreamFrameInfo {
                result[AnyHashable(key)] = value
            } else if let key = key as? String {
                result[AnyHashable(key)] = value
            } else if let key = key as? NSString {
                result[AnyHashable(key as String)] = value
            }
        }

        return result.isEmpty ? nil : result
    }

    private func frameStatusRawValue(from attachments: [AnyHashable: Any]) -> Int? {
        let value = attachments[AnyHashable(SCStreamFrameInfo.status)]
            ?? attachments[AnyHashable(SCStreamFrameInfo.status.rawValue)]

        if let value = value as? SCFrameStatus {
            return value.rawValue
        }

        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
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
        let pixelSize = (try? request.pixelSize.roundedToEvenDimensions) ?? request.pixelSize

        return [
            AVVideoCodecKey: request.videoCodec.avVideoCodecType,
            AVVideoWidthKey: pixelSize.width,
            AVVideoHeightKey: pixelSize.height
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

private struct RecordingAudioLevelMixer {
    private let capturesSystemAudio: Bool
    private let capturesMicrophone: Bool
    private var systemSample = AudioLevelSample.silent
    private var microphoneSample = AudioLevelSample.silent

    init(audio: RecordingAudioMode) {
        self.capturesSystemAudio = audio.capturesSystemAudio
        self.capturesMicrophone = audio.capturesMicrophone
    }

    mutating func update(_ sample: AudioLevelSample, outputType: SCStreamOutputType) -> AudioLevelSample? {
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

        return AudioLevelSample.combined([
            capturesSystemAudio ? systemSample : nil,
            capturesMicrophone ? microphoneSample : nil
        ].compactMap { $0 })
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
