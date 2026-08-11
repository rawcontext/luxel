@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

extension SegmentedSCStreamReplayEngine {
    func replayTarget(for source: ReplayBufferSource) -> CaptureTarget {
        switch source {
        case .display(let displayID):
            .display(displayID)
        case .displayWithCursor:
            .display(DisplayID(CGMainDisplayID()))
        }
    }

    func makeStreamConfiguration(
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

    func pixelSize(contentRect: CGRect, pointPixelScale: Float) -> PixelSize {
        let pointScale = max(CGFloat(pointPixelScale), 1)
        let width = max(1, Int((contentRect.width * pointScale).rounded()))
        let height = max(1, Int((contentRect.height * pointScale).rounded()))
        return (try? PixelSize(width: width, height: height).roundedToEvenDimensions)
            ?? .fullHD1920x1080
    }

    func setActiveSession(
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

    func clearActiveSessionIfMatching(_ session: ReplayBufferCaptureSession) async throws {
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

    func updateStartingState(since: Date) async throws {
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

    func publishBufferingIfReady() {
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

    func stopActiveSession(removeFiles: Bool) async throws {
        let session = await activeSessionForStopping()
        guard let session else {
            return
        }

        try await stopStreamCapture(session.stream)
        try await finishSession(session, removeFiles: removeFiles)
    }

    func activeSessionForStopping() async -> ReplayBufferCaptureSession? {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                continuation.resume(returning: activeSession)
            }
        }
    }

    func finishSession(
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

    func makeClipPlan(
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

    func releaseClipPlan(_ plan: ReplayBufferClipPlan) async {
        await withCheckedContinuation { continuation in
            sampleHandlerQueue.async { [self] in
                activeSession?.releaseProtectedSegments(plan.segmentIDs, fileManager: fileManager)
                continuation.resume()
            }
        }
    }

    func materializeClip(_ plan: ReplayBufferClipPlan) async throws {
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

            try await trimClip(
                temporaryURL,
                outputURL: plan.outputURL,
                trimStart: plan.trimStartOffset ?? 0,
                requestedDuration: plan.requestedDuration
            )
            try? fileManager.removeItem(at: temporaryURL)
        } catch {
            try? handle.close()
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: plan.outputURL)
            throw error
        }
    }

    func trimClip(
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

    func makeClipOutputURL() throws -> URL {
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

    func stateAfterClipping() -> ReplayBufferState {
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

    func startStreamCapture(_ stream: SCStream) async throws {
        try await ScreenCaptureKitStreamLifecycle.start(stream, timeout: streamStartTimeout) {
            ReplayBufferEngineError.armFailed("Timed out starting capture")
        }
    }

    func stopStreamCapture(_ stream: SCStream) async throws {
        try await ScreenCaptureKitStreamLifecycle.stop(stream, timeout: streamStopTimeout)
    }
}
