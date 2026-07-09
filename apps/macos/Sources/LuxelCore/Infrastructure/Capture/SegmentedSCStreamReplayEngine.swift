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
