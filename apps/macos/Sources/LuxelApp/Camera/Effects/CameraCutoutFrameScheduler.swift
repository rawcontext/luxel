import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import LuxelCore
import OSLog

struct CameraCutoutFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
}

struct CameraCutoutRenderedFrame: @unchecked Sendable {
    let image: CGImage
}

struct CameraCutoutSchedulerSnapshot: Equatable, Sendable {
    let inFlightCount: Int
    let pendingCount: Int
    let droppedFrameCount: Int
}

final class CameraCutoutFrameScheduler<Frame: Sendable, Output: Sendable>: @unchecked Sendable {
    typealias Processor = @Sendable (Frame, UInt64) throws -> Output
    typealias OutputHandler = @Sendable (Output) -> Void
    typealias FailureHandler = @Sendable (any Error) -> Void

    private let lock = NSLock()
    private let processingQueue: DispatchQueue
    private let process: Processor
    private let onOutput: OutputHandler
    private let onFailure: FailureHandler
    private var generation: UInt64 = 0
    private var isActive = false
    private var isProcessing = false
    private var pendingFrame: Frame?
    private var droppedFrameCount = 0

    init(
        queueLabel: String = "media.luxel.cameraCutout.inference",
        process: @escaping Processor,
        onOutput: @escaping OutputHandler,
        onFailure: @escaping FailureHandler
    ) {
        processingQueue = DispatchQueue(label: queueLabel, qos: .userInteractive)
        self.process = process
        self.onOutput = onOutput
        self.onFailure = onFailure
    }

    @discardableResult
    func start() -> UInt64 {
        lock.withLock {
            generation &+= 1
            isActive = true
            isProcessing = false
            pendingFrame = nil
            droppedFrameCount = 0
            return generation
        }
    }

    func submit(_ frame: Frame) {
        let work: (Frame, UInt64)? = lock.withLock {
            guard isActive else {
                return nil
            }
            if isProcessing {
                if pendingFrame != nil {
                    droppedFrameCount += 1
                    Self.logger.debug("Dropped stale Cutout camera frame")
                }
                pendingFrame = frame
                return nil
            }

            isProcessing = true
            return (frame, generation)
        }

        if let work {
            enqueue(work.0, generation: work.1)
        }
    }

    func stop() {
        lock.withLock {
            generation &+= 1
            isActive = false
            pendingFrame = nil
        }
    }

    var snapshot: CameraCutoutSchedulerSnapshot {
        lock.withLock {
            CameraCutoutSchedulerSnapshot(
                inFlightCount: isProcessing ? 1 : 0,
                pendingCount: pendingFrame == nil ? 0 : 1,
                droppedFrameCount: droppedFrameCount
            )
        }
    }

    private func enqueue(_ frame: Frame, generation: UInt64) {
        processingQueue.async { [self] in
            do {
                let output = try process(frame, generation)
                finish(output: output, failure: nil, generation: generation)
            } catch {
                finish(output: nil, failure: error, generation: generation)
            }
        }
    }

    private func finish(output: Output?, failure: (any Error)?, generation: UInt64) {
        let result: FinishResult = lock.withLock {
            guard isActive, self.generation == generation else {
                return .ignored
            }
            if let failure {
                isActive = false
                isProcessing = false
                pendingFrame = nil
                return .failed(failure)
            }

            let nextFrame = pendingFrame
            pendingFrame = nil
            isProcessing = nextFrame != nil
            return .completed(output, nextFrame)
        }

        switch result {
        case .ignored:
            break
        case .failed(let error):
            Self.logger.error("Cutout frame processing failed: \(error.localizedDescription, privacy: .public)")
            onFailure(error)
        case .completed(let output, let nextFrame):
            if let output, isCurrent(generation) {
                onOutput(output)
            }
            if let nextFrame {
                enqueue(nextFrame, generation: generation)
            }
        }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        lock.withLock { isActive && self.generation == generation }
    }

    private enum FinishResult {
        case ignored
        case failed(any Error)
        case completed(Output?, Frame?)
    }

    private static var logger: Logger {
        Logger(subsystem: "media.luxel.app", category: "CameraCutout")
    }
}

final class CameraCutoutCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
                                         @unchecked Sendable {
    private let scheduler: CameraCutoutFrameScheduler<CameraCutoutFrame, CameraCutoutRenderedFrame>

    init(scheduler: CameraCutoutFrameScheduler<CameraCutoutFrame, CameraCutoutRenderedFrame>) {
        self.scheduler = scheduler
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        scheduler.submit(
            CameraCutoutFrame(
                pixelBuffer: pixelBuffer,
                timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            )
        )
    }
}

final class CameraCutoutSessionPipeline: @unchecked Sendable {
    let videoOutput: AVCaptureVideoDataOutput

    private let captureQueue = DispatchQueue(label: "media.luxel.cameraCutout.capture")
    private let compositor: CameraCutoutCompositor
    private let scheduler: CameraCutoutFrameScheduler<CameraCutoutFrame, CameraCutoutRenderedFrame>
    private let captureDelegate: CameraCutoutCaptureDelegate

    init(
        processor: MODNetPortraitMattingProcessor,
        outputSize: CGSize,
        isMirrored: Bool,
        onImage: @escaping @Sendable (CGImage) -> Void,
        onFailure: @escaping @Sendable (any Error) -> Void
    ) {
        let compositor = CameraCutoutCompositor()
        self.compositor = compositor
        scheduler = CameraCutoutFrameScheduler(
            process: { frame, generation in
                let matte = try processor.alphaMatte(for: frame.pixelBuffer)
                let image = try compositor.composite(
                    cameraFrame: frame.pixelBuffer,
                    alphaMatte: matte,
                    outputSize: outputSize,
                    isMirrored: isMirrored,
                    timestamp: frame.timestamp,
                    generation: generation
                )
                return CameraCutoutRenderedFrame(image: image)
            },
            onOutput: { frame in onImage(frame.image) },
            onFailure: onFailure
        )
        captureDelegate = CameraCutoutCaptureDelegate(scheduler: scheduler)
        videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
    }

    func start() {
        compositor.reset()
        scheduler.start()
        videoOutput.setSampleBufferDelegate(captureDelegate, queue: captureQueue)
    }

    func stop() {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        scheduler.stop()
        compositor.reset()
    }
}
