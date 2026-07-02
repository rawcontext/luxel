@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

public final class SegmentedSCStreamReplayEngine: NSObject, ReplayBufferEngine, @unchecked Sendable {
    private let contentFilterProvider: any ScreenCaptureKitContentFilterProvider
    private let storageDirectory: URL
    private let clipDirectoryProvider: @Sendable () -> URL
    private let fileManager: FileManager
    private let dateProvider: any DateProvider
    private let stateBroadcaster = ReplayBufferStateBroadcaster()
    private let sampleHandlerQueue = DispatchQueue(label: "media.luxel.replay-buffer-engine")
    private let streamStartTimeout: Duration = .seconds(10)
    private let streamStopTimeout: Duration = .seconds(5)
    private let segmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
    private var activeSession: ReplayBufferCaptureSession?
    private var currentConfiguration: ReplayBufferConfiguration?
    private var bufferingSince: Date?
    private var pausedReason: ReplayBufferPauseReason?
    private var isReadyForClipping = false

    public init(
        contentFilterProvider: any ScreenCaptureKitContentFilterProvider =
            ShareableContentFilterProvider(),
        storageDirectory: URL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )
        .first?
        .appending(path: "Luxel", directoryHint: .isDirectory)
        .appending(path: "ReplayBuffer", directoryHint: .isDirectory)
        ?? FileManager.default.temporaryDirectory
        .appending(path: "LuxelReplayBuffer", directoryHint: .isDirectory),
        clipDirectoryProvider: @escaping @Sendable () -> URL,
        fileManager: FileManager = .default,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.contentFilterProvider = contentFilterProvider
        self.storageDirectory = storageDirectory
        self.clipDirectoryProvider = clipDirectoryProvider
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        super.init()
    }

    public var state: AsyncStream<ReplayBufferState> {
        stateBroadcaster.stream()
    }

    public func arm(configuration: ReplayBufferConfiguration) async throws {
        try await stopActiveSession(removeFiles: true)

        let target = replayTarget(for: configuration.source)
        let contentFilter = try await contentFilterProvider.contentFilter(for: target)
        let stream = SCStream(
            filter: contentFilter,
            configuration: makeStreamConfiguration(
                configuration,
                contentRect: contentFilter.contentRect,
                pointPixelScale: contentFilter.pointPixelScale
            ),
            delegate: nil
        )
        let sessionDirectory =
            storageDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let session = try ReplayBufferCaptureSession(
            configuration: configuration,
            stream: stream,
            sessionDirectory: sessionDirectory,
            pixelSize: pixelSize(
                contentRect: contentFilter.contentRect,
                pointPixelScale: contentFilter.pointPixelScale
            ),
            segmentInterval: segmentInterval,
            delegate: self,
            fileManager: fileManager
        )

        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleHandlerQueue)
            if configuration.includeSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleHandlerQueue)
            }
            try await setActiveSession(session, configuration: configuration)
            try await startStreamCapture(stream)
            let since = dateProvider.now()
            try await updateStartingState(since: since)
        } catch {
            await session.cancel(fileManager: fileManager)
            try? await clearActiveSessionIfMatching(session)
            throw ReplayBufferEngineError.armFailed(error.localizedReplayBufferDescription)
        }
    }

    public func pause(reason: ReplayBufferPauseReason) async throws {
        pausedReason = reason
        try await stopActiveSession(removeFiles: true)
        stateBroadcaster.publish(.paused(reason: reason))
    }

    public func resume() async throws {
        guard let configuration = currentConfiguration else {
            return
        }

        pausedReason = nil
        try await arm(configuration: configuration)
    }

    public func disarm() async throws {
        currentConfiguration = nil
        bufferingSince = nil
        pausedReason = nil
        isReadyForClipping = false
        try await stopActiveSession(removeFiles: true)
        stateBroadcaster.publish(.disarmed)
    }

    public func clip(lastSeconds: TimeInterval) async throws -> URL {
        guard lastSeconds.isFinite, lastSeconds > 0 else {
            throw ReplayBufferModelError.invalidClipDuration
        }

        let previousState = stateAfterClipping()
        stateBroadcaster.publish(.clipping)

        do {
            let outputURL = try makeClipOutputURL()
            let plan = try await makeClipPlan(lastSeconds: lastSeconds, outputURL: outputURL)
            try await materializeClip(plan)
            await releaseClipPlan(plan)
            stateBroadcaster.publish(previousState)
            return outputURL
        } catch {
            stateBroadcaster.publish(previousState)
            throw error
        }
    }
}

extension SegmentedSCStreamReplayEngine: SCStreamOutput {
    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        activeSession?.append(sampleBuffer, outputType: type, fileManager: fileManager)
    }
}

extension SegmentedSCStreamReplayEngine: AVAssetWriterDelegate {
    public func assetWriter(
        _ writer: AVAssetWriter,
        didOutputSegmentData segmentData: Data,
        segmentType: AVAssetSegmentType,
        segmentReport: AVAssetSegmentReport?
    ) {
        let retainedData = Data(segmentData)
        sampleHandlerQueue.async { [weak self] in
            guard let self else {
                return
            }

            let event = self.activeSession?.storeSegment(
                retainedData,
                type: segmentType,
                report: segmentReport,
                fileManager: self.fileManager
            )

            if event == .clipBecameAvailable {
                self.publishBufferingIfReady()
            }
        }
    }
}

extension SegmentedSCStreamReplayEngine {
    private func replayTarget(for source: ReplayBufferSource) -> CaptureTarget {
        switch source {
        case .display(let displayID):
            .display(displayID)
        case .displayWithCursor:
            .display(DisplayID(CGMainDisplayID()))
        }
    }

    private func makeStreamConfiguration(
        _ configuration: ReplayBufferConfiguration,
        contentRect: CGRect,
        pointPixelScale: Float
    ) -> SCStreamConfiguration {
        let streamConfiguration = SCStreamConfiguration()
        let pixelSize = pixelSize(contentRect: contentRect, pointPixelScale: pointPixelScale)
        streamConfiguration.width = size_t(pixelSize.width)
        streamConfiguration.height = size_t(pixelSize.height)
        streamConfiguration.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(configuration.frameRate.framesPerSecond)
        )
        streamConfiguration.showsCursor = true
        streamConfiguration.showMouseClicks = false
        streamConfiguration.pixelFormat = kCVPixelFormatType_32BGRA
        streamConfiguration.capturesAudio = configuration.includeSystemAudio
        streamConfiguration.excludesCurrentProcessAudio = configuration.includeSystemAudio
        streamConfiguration.sampleRate = 48_000
        streamConfiguration.channelCount = 2
        streamConfiguration.queueDepth = 8
        return streamConfiguration
    }

    private func pixelSize(contentRect: CGRect, pointPixelScale: Float) -> PixelSize {
        let pointScale = max(CGFloat(pointPixelScale), 1)
        let width = max(1, Int((contentRect.width * pointScale).rounded()))
        let height = max(1, Int((contentRect.height * pointScale).rounded()))
        return (try? PixelSize(width: width, height: height).roundedToEvenDimensions)
            ?? .fullHD1920x1080
    }

    private func setActiveSession(
        _ session: ReplayBufferCaptureSession,
        configuration: ReplayBufferConfiguration
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                activeSession = session
                currentConfiguration = configuration
                isReadyForClipping = false
                continuation.resume()
            }
        }
    }

    private func clearActiveSessionIfMatching(_ session: ReplayBufferCaptureSession) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                if activeSession === session {
                    activeSession = nil
                    isReadyForClipping = false
                }
                continuation.resume()
            }
        }
    }

    private func updateStartingState(since: Date) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                bufferingSince = since
                pausedReason = nil
                if activeSession?.canMakeClipPlan == true {
                    isReadyForClipping = true
                    stateBroadcaster.publish(.buffering(since: since))
                } else {
                    isReadyForClipping = false
                    stateBroadcaster.publish(.starting(since: since))
                }
                continuation.resume()
            }
        }
    }

    private func publishBufferingIfReady() {
        guard !isReadyForClipping,
              pausedReason == nil,
              activeSession?.canMakeClipPlan == true,
              let bufferingSince
        else {
            return
        }

        isReadyForClipping = true
        stateBroadcaster.publish(.buffering(since: bufferingSince))
    }

    private func stopActiveSession(removeFiles: Bool) async throws {
        let session = await activeSessionForStopping()
        guard let session else {
            return
        }

        try await stopStreamCapture(session.stream)
        try await finishSession(session, removeFiles: removeFiles)
    }

    private func activeSessionForStopping() async -> ReplayBufferCaptureSession? {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                continuation.resume(returning: activeSession)
            }
        }
    }

    private func finishSession(
        _ session: ReplayBufferCaptureSession,
        removeFiles: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                session.finish(fileManager: fileManager) { result in
                    self.sampleHandlerQueue.async {
                        if self.activeSession === session {
                            self.activeSession = nil
                            self.isReadyForClipping = false
                        }
                        if removeFiles {
                            session.removeFiles(fileManager: self.fileManager)
                        }
                        continuation.resume(with: result)
                    }
                }
            }
        }
    }

    private func makeClipPlan(
        lastSeconds: TimeInterval,
        outputURL: URL
    ) async throws -> ReplayBufferClipPlan {
        try await withCheckedThrowingContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                do {
                    guard let activeSession else {
                        throw ReplayBufferEngineError.notBuffering
                    }

                    continuation.resume(
                        returning: try activeSession.makeClipPlan(
                            lastSeconds: lastSeconds,
                            outputURL: outputURL,
                            fileManager: fileManager
                        ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func releaseClipPlan(_ plan: ReplayBufferClipPlan) async {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                activeSession?.releaseProtectedSegments(plan.segmentIDs, fileManager: fileManager)
                continuation.resume()
            }
        }
    }

    private func materializeClip(_ plan: ReplayBufferClipPlan) async throws {
        let temporaryURL = plan.outputURL
            .deletingLastPathComponent()
            .appending(path: ".\(plan.outputURL.deletingPathExtension().lastPathComponent)-raw")
            .appendingPathExtension("mp4")

        try? fileManager.removeItem(at: temporaryURL)
        try fileManager.createDirectory(
            at: temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.write(contentsOf: plan.initializationSegmentData)
            for segmentURL in plan.segmentFileURLs {
                try handle.write(contentsOf: Data(contentsOf: segmentURL))
            }
            try handle.close()

            if let trimStart = plan.trimStartOffset, trimStart > 0 {
                try await trimClip(
                    temporaryURL,
                    outputURL: plan.outputURL,
                    trimStart: trimStart,
                    requestedDuration: plan.requestedDuration
                )
                try? fileManager.removeItem(at: temporaryURL)
            } else {
                try? fileManager.removeItem(at: plan.outputURL)
                try fileManager.moveItem(at: temporaryURL, to: plan.outputURL)
            }
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: plan.outputURL)
            throw error
        }
    }

    private func trimClip(
        _ inputURL: URL,
        outputURL: URL,
        trimStart: TimeInterval,
        requestedDuration: TimeInterval
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let start = CMTime(seconds: trimStart, preferredTimescale: 600)
        let requested = CMTime(seconds: requestedDuration, preferredTimescale: 600)
        let remaining = max(.zero, CMTimeSubtract(duration, start))
        let trimDuration = min(requested, remaining)
        guard trimDuration > .zero else {
            throw ReplayBufferEngineError.emptyClip
        }

        guard
            let exportSession = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetPassthrough
            )
        else {
            throw ReplayBufferEngineError.exportUnavailable
        }
        guard exportSession.supportedFileTypes.contains(.mp4) else {
            throw ReplayBufferEngineError.exportUnavailable
        }

        try? fileManager.removeItem(at: outputURL)
        exportSession.timeRange = CMTimeRange(start: start, duration: trimDuration)
        try await exportSession.export(to: outputURL, as: .mp4)
    }

    private func makeClipOutputURL() throws -> URL {
        let clipDirectory = clipDirectoryProvider()
        try fileManager.createDirectory(at: clipDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let fileName = "Luxel Replay \(formatter.string(from: dateProvider.now()))"
        var outputURL =
            clipDirectory
            .appending(path: fileName)
            .appendingPathExtension("mp4")
        var suffix = 2
        while fileManager.fileExists(atPath: outputURL.path) {
            outputURL =
                clipDirectory
                .appending(path: "\(fileName) \(suffix)")
                .appendingPathExtension("mp4")
            suffix += 1
        }
        return outputURL
    }

    private func stateAfterClipping() -> ReplayBufferState {
        if let pausedReason {
            return .paused(reason: pausedReason)
        }

        if let bufferingSince {
            return isReadyForClipping
                ? .buffering(since: bufferingSince)
                : .starting(since: bufferingSince)
        }

        return .disarmed
    }

    private func startStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStartTimeout

        try await withCheckedThrowingContinuation { continuation in
            let completion = ReplayBufferCompletion(continuation)
            let streamHandle = ReplayBufferStreamHandle(stream)
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
                    let timeoutError = ReplayBufferEngineError.armFailed("Timed out starting capture")
                    if completion.resume(with: .failure(timeoutError)) {
                        streamHandle.stopCaptureIgnoringResult()
                    }
                } catch {
                    return
                }
            }
        }
    }

    private func stopStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStopTimeout

        try await withCheckedThrowingContinuation { continuation in
            let completion = ReplayBufferCompletion(continuation)
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
                } catch {
                    return
                }
            }
        }
    }
}

public enum ReplayBufferEngineError: Error, Equatable {
    case armFailed(String)
    case notBuffering
    case missingInitializationSegment
    case missingSegments
    case emptyClip
    case exportUnavailable
}

extension ReplayBufferEngineError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .armFailed(let message):
            "Replay buffer failed to start: \(message)"
        case .notBuffering:
            "Replay buffer is not currently buffering"
        case .missingInitializationSegment:
            "Replay buffer is still getting ready"
        case .missingSegments:
            "Replay buffer has not captured enough video yet"
        case .emptyClip:
            "Replay buffer clip is empty"
        case .exportUnavailable:
            "Replay buffer clip export is unavailable"
        }
    }
}

private final class ReplayBufferCaptureSession: @unchecked Sendable {
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
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            )
        else {
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
        let value =
            attachments[AnyHashable(SCStreamFrameInfo.status)]
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

}

private struct ReplayBufferSegmentTiming {
    let start: TimeInterval
    let duration: TimeInterval
}

private enum ReplayBufferSegmentStorageEvent: Equatable {
    case clipBecameAvailable
}

private struct ReplayBufferClipPlan: Sendable {
    let outputURL: URL
    let initializationSegmentData: Data
    let segmentFileURLs: [URL]
    let segmentIDs: Set<String>
    let trimStartOffset: TimeInterval?
    let requestedDuration: TimeInterval
}

private final class ReplayBufferStateBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: ReplayBufferState = .disarmed
    private var continuations: [UUID: AsyncStream<ReplayBufferState>.Continuation] = [:]

    func stream() -> AsyncStream<ReplayBufferState> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            let state = lock.withLock {
                continuations[id] = continuation
                return currentState
            }
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    func publish(_ state: ReplayBufferState) {
        let activeContinuations = lock.withLock {
            currentState = state
            return Array(continuations.values)
        }

        activeContinuations.forEach { $0.yield(state) }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}

private final class ReplayBufferCompletion: @unchecked Sendable {
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

private struct ReplayBufferStreamHandle: @unchecked Sendable {
    private let stream: SCStream

    init(_ stream: SCStream) {
        self.stream = stream
    }

    func stopCaptureIgnoringResult() {
        stream.stopCapture { _ in }
    }
}

extension Error {
    fileprivate var localizedReplayBufferDescription: String {
        if let errorDescription = (self as? LocalizedError)?.errorDescription, !errorDescription.isEmpty {
            return errorDescription
        }

        let localizedDescription = (self as NSError).localizedDescription
        return localizedDescription.isEmpty ? String(describing: self) : localizedDescription
    }
}
