@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

public final class SegmentedSCStreamReplayEngine: NSObject, ReplayBufferEngine, @unchecked Sendable {
    let contentFilterProvider: any ScreenCaptureKitContentFilterProvider
    let storageDirectory: URL
    let clipDirectoryProvider: @Sendable () -> URL
    let fileManager: FileManager
    let dateProvider: any DateProvider
    let stateBroadcaster = ReplayBufferStateBroadcaster()
    let sampleHandlerQueue = DispatchQueue(label: "media.luxel.replay-buffer-engine")
    let streamStartTimeout: Duration = .seconds(10)
    let streamStopTimeout: Duration = .seconds(5)
    let segmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
    var activeSession: ReplayBufferCaptureSession?
    var currentConfiguration: ReplayBufferConfiguration?
    var bufferingSince: Date?
    var pausedReason: ReplayBufferPauseReason?
    var isReadyForClipping = false

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
            throw ReplayBufferEngineError.armFailed(error.preferredLocalizedDescription)
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

final class ReplayBufferStateBroadcaster: @unchecked Sendable {
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
