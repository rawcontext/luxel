@preconcurrency import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

final class ReplayBufferCaptureSession: @unchecked Sendable {
    let stream: SCStream
    private let configuration: ReplayBufferConfiguration
    private let sessionDirectory: URL
    private let segmentsDirectory: URL
    private let initializationSegmentURL: URL
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let segmentDuration: TimeInterval
    private var ledger: SegmentLedger
    private var mediaSegmentFileURLs: [String: URL] = [:]
    private var protectedSegmentIDs: Set<String> = []
    private var segmentIndex = 0
    private var initialSourceTime: CMTime?
    private var hasStartedWriting = false
    private(set) var hasInitializationSegment = false
    private var pendingError: (any Error)?

    var canMakeClipPlan: Bool {
        hasInitializationSegment && !ledger.segments.isEmpty
    }

    init(
        configuration: ReplayBufferConfiguration,
        stream: SCStream,
        sessionDirectory: URL,
        pixelSize: PixelSize,
        segmentInterval: CMTime,
        delegate: AVAssetWriterDelegate,
        fileManager: FileManager
    ) throws {
        self.configuration = configuration
        self.stream = stream
        self.sessionDirectory = sessionDirectory
        self.segmentsDirectory = sessionDirectory.appending(
            path: "Segments", directoryHint: .isDirectory)
        self.initializationSegmentURL = sessionDirectory.appending(path: "init.mp4")
        self.writer = AVAssetWriter(contentType: .mpeg4Movie)
        self.segmentDuration = max(0.001, segmentInterval.seconds)
        self.ledger = try SegmentLedger(bufferLength: configuration.bufferLength)

        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)

        writer.outputFileTypeProfile = .mpeg4AppleHLS
        writer.preferredOutputSegmentInterval = segmentInterval
        writer.delegate = delegate

        let roundedPixelSize = (try? pixelSize.roundedToEvenDimensions) ?? pixelSize
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: roundedPixelSize.width,
                AVVideoHeightKey: roundedPixelSize.height
            ]
        )
        videoInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(videoInput) else {
            throw ReplayBufferEngineError.armFailed("Cannot add replay video writer input")
        }
        writer.add(videoInput)
        self.videoInput = videoInput

        if configuration.includeSystemAudio {
            let audioInput = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            )
            audioInput.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioInput) else {
                throw ReplayBufferEngineError.armFailed("Cannot add replay audio writer input")
            }
            writer.add(audioInput)
            systemAudioInput = audioInput
        } else {
            systemAudioInput = nil
        }
    }
}

extension ReplayBufferCaptureSession {

    func append(
        _ sampleBuffer: CMSampleBuffer,
        outputType: SCStreamOutputType,
        fileManager: FileManager
    ) {
        guard pendingError == nil, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        let isCompleteScreenFrame =
            outputType == .screen && sampleBufferContainsCompleteFrame(sampleBuffer)
        if outputType == .screen, !isCompleteScreenFrame {
            return
        }

        guard let input = input(for: outputType) else {
            return
        }

        if !hasStartedWriting {
            guard isCompleteScreenFrame else {
                return
            }

            startWritingIfNeeded(for: sampleBuffer)
        }

        guard writer.status == .writing else {
            pendingError =
                writer.error ?? ReplayBufferEngineError.armFailed(String(describing: writer.status))
            return
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        if !input.append(sampleBuffer), let error = writer.error {
            pendingError = error
        }
    }

    func storeSegment(
        _ data: Data,
        type: AVAssetSegmentType,
        report: AVAssetSegmentReport?,
        fileManager: FileManager
    ) -> ReplayBufferSegmentStorageEvent? {
        let couldMakeClipPlan = canMakeClipPlan
        do {
            switch type {
            case .initialization:
                try data.write(to: initializationSegmentURL, options: .atomic)
                hasInitializationSegment = true
                return readinessEvent(couldMakeClipPlan: couldMakeClipPlan)
            case .separable:
                let timing = segmentTiming(from: report)
                let id = "segment-\(segmentIndex)"
                segmentIndex += 1
                let fileURL =
                    segmentsDirectory
                    .appending(path: id)
                    .appendingPathExtension("m4s")
                try data.write(to: fileURL, options: .atomic)
                let segment = try ReplayBufferSegment(
                    id: id,
                    start: timing.start,
                    duration: timing.duration
                )
                ledger = try ledger.appending(segment)
                mediaSegmentFileURLs[id] = fileURL
                evictUnreferencedSegments(fileManager: fileManager)
                return readinessEvent(couldMakeClipPlan: couldMakeClipPlan)
            default:
                return nil
            }
        } catch {
            pendingError = error
            return nil
        }
    }

    func makeClipPlan(
        lastSeconds: TimeInterval,
        outputURL: URL,
        fileManager: FileManager
    ) throws -> ReplayBufferClipPlan {
        if let pendingError {
            throw pendingError
        }

        guard hasInitializationSegment,
            fileManager.fileExists(atPath: initializationSegmentURL.path)
        else {
            throw ReplayBufferEngineError.missingInitializationSegment
        }

        let coverage = try ledger.segmentsCovering(lastSeconds: lastSeconds)
        guard !coverage.segments.isEmpty else {
            throw ReplayBufferEngineError.missingSegments
        }

        let segmentFileURLs = try coverage.segments.map { segment in
            guard let fileURL = mediaSegmentFileURLs[segment.id],
                fileManager.fileExists(atPath: fileURL.path)
            else {
                throw ReplayBufferEngineError.missingSegments
            }

            return fileURL
        }
        let segmentIDs = Set(coverage.segments.map(\.id))
        protectedSegmentIDs.formUnion(segmentIDs)

        return ReplayBufferClipPlan(
            outputURL: outputURL,
            initializationSegmentData: try Data(contentsOf: initializationSegmentURL),
            segmentFileURLs: segmentFileURLs,
            segmentIDs: segmentIDs,
            trimStartOffset: coverage.trimStartOffset,
            requestedDuration: coverage.requestedDuration
        )
    }

    func releaseProtectedSegments(_ segmentIDs: Set<String>, fileManager: FileManager) {
        protectedSegmentIDs.subtract(segmentIDs)
        evictUnreferencedSegments(fileManager: fileManager)
    }

    private func readinessEvent(couldMakeClipPlan: Bool) -> ReplayBufferSegmentStorageEvent? {
        !couldMakeClipPlan && canMakeClipPlan ? .clipBecameAvailable : nil
    }

    func finish(
        fileManager: FileManager,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        if let pendingError {
            writer.cancelWriting()
            completion(.failure(pendingError))
            return
        }

        guard hasStartedWriting else {
            writer.cancelWriting()
            completion(.success(()))
            return
        }

        videoInput.markAsFinished()
        systemAudioInput?.markAsFinished()
        writer.finishWriting { [self] in
            switch writer.status {
            case .completed:
                completion(.success(()))
            case .failed, .cancelled:
                completion(
                    .failure(
                        writer.error ?? ReplayBufferEngineError.armFailed(String(describing: writer.status))))
            case .unknown, .writing:
                completion(.failure(ReplayBufferEngineError.armFailed(String(describing: writer.status))))
            @unknown default:
                completion(.failure(ReplayBufferEngineError.armFailed(String(describing: writer.status))))
            }
        }
    }

    func cancel(fileManager: FileManager) async {
        writer.cancelWriting()
        removeFiles(fileManager: fileManager)
    }

    func removeFiles(fileManager: FileManager) {
        try? fileManager.removeItem(at: sessionDirectory)
    }

    private func startWritingIfNeeded(for sampleBuffer: CMSampleBuffer) {
        guard !hasStartedWriting else {
            return
        }

        let startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard startTime.isValid else {
            pendingError = ReplayBufferEngineError.armFailed("Cannot read replay start time")
            return
        }

        writer.initialSegmentStartTime = startTime
        guard writer.startWriting() else {
            pendingError = writer.error ?? ReplayBufferEngineError.armFailed("Cannot start replay writer")
            return
        }

        writer.startSession(atSourceTime: startTime)
        initialSourceTime = startTime
        hasStartedWriting = true
    }

    private func input(for outputType: SCStreamOutputType) -> AVAssetWriterInput? {
        switch outputType {
        case .screen:
            videoInput
        case .audio:
            systemAudioInput
        case .microphone:
            nil
        @unknown default:
            nil
        }
    }

    private func segmentTiming(from report: AVAssetSegmentReport?) -> ReplayBufferSegmentTiming {
        guard let initialSourceTime else {
            return fallbackSegmentTiming()
        }

        let videoReport = report?.trackReports.first { $0.mediaType == .video }
        guard let videoReport,
            videoReport.earliestPresentationTimeStamp.isValid,
            videoReport.duration.isValid,
            videoReport.duration > .zero
        else {
            return fallbackSegmentTiming()
        }

        let rawStart = CMTimeSubtract(videoReport.earliestPresentationTimeStamp, initialSourceTime)
            .seconds
        let start = max(ledger.segments.last?.end ?? 0, max(0, rawStart))
        return ReplayBufferSegmentTiming(
            start: start,
            duration: max(0.001, videoReport.duration.seconds)
        )
    }

    private func fallbackSegmentTiming() -> ReplayBufferSegmentTiming {
        ReplayBufferSegmentTiming(
            start: ledger.segments.last?.end ?? 0,
            duration: segmentDuration
        )
    }

    private func evictUnreferencedSegments(fileManager: FileManager) {
        let retainedIDs = Set(ledger.segments.map(\.id)).union(protectedSegmentIDs)
        for (id, fileURL) in mediaSegmentFileURLs where !retainedIDs.contains(id) {
            try? fileManager.removeItem(at: fileURL)
            mediaSegmentFileURLs[id] = nil
        }
    }

    private func sampleBufferContainsCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        ScreenCaptureKitSampleAttachments.containsCompleteFrame(sampleBuffer)
    }

}
