@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

public actor FluidAudioVoiceActivityDetector: VoiceActivityDetecting {
    private let modelLocator: BundledVoiceActivityModelLocator
    private var activeSession: ActiveVoiceActivityDetectionSession?

    public init(modelLocator: BundledVoiceActivityModelLocator = .init()) {
        self.modelLocator = modelLocator
    }

    public func start(deviceID: String?) async -> AsyncStream<VoiceActivityDetectorEvent> {
        await stop()

        let events = AsyncStream.makeStream(
            of: VoiceActivityDetectorEvent.self,
            bufferingPolicy: .bufferingNewest(8)
        )

        do {
            guard let modelURL = modelLocator.modelURL else {
                throw VoiceActivityDetectionFailure.modelUnavailable
            }

            let configuration = MLModelConfiguration()
            configuration.computeUnits = VadConfig.default.computeUnits
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            let manager = VadManager(config: .default, vadModel: model)
            let capture = try VoiceActivityCaptureSession(deviceID: deviceID)
            let worker = Task {
                await Self.process(
                    capture: capture,
                    manager: manager,
                    continuation: events.continuation
                )
            }
            let session = ActiveVoiceActivityDetectionSession(
                capture: capture,
                worker: worker,
                continuation: events.continuation
            )
            activeSession = session
            events.continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.stop(sessionID: session.id)
                }
            }
            await capture.start()
        } catch let failure as VoiceActivityDetectionFailure {
            events.continuation.yield(.failed(failure))
            events.continuation.finish()
        } catch {
            events.continuation.yield(.failed(.modelUnavailable))
            events.continuation.finish()
        }

        return events.stream
    }

    public func stop() async {
        guard let session = activeSession else {
            return
        }

        activeSession = nil
        await session.capture.stop()
        await session.worker.value
        session.continuation.finish()
    }

    private func stop(sessionID: UUID) async {
        guard activeSession?.id == sessionID else {
            return
        }
        await stop()
    }

    private static func process(
        capture: VoiceActivityCaptureSession,
        manager: VadManager,
        continuation: AsyncStream<VoiceActivityDetectorEvent>.Continuation
    ) async {
        var pipeline = await VoiceActivityInferencePipeline(manager: manager)

        for await capturedBuffer in capture.buffers {
            guard !Task.isCancelled else {
                break
            }

            if capture.takeOverflow() {
                await pipeline.reset()
                continuation.yield(.reset(.queueOverflow))
            } else if pipeline.hasDiscontinuity(at: capturedBuffer.presentationTime) {
                await pipeline.reset()
                continuation.yield(.reset(.discontinuity))
            }

            do {
                for observation in try await pipeline.process(capturedBuffer) {
                    continuation.yield(.observation(observation))
                }
            } catch is VoiceActivityAudioConversionError {
                continuation.yield(.failed(.conversionFailed))
                break
            } catch {
                continuation.yield(.failed(.inferenceFailed))
                break
            }
        }

        continuation.finish()
    }

    fileprivate static func observationKind(
        for event: VadStreamEvent?
    ) -> VoiceActivityObservationKind {
        switch event?.kind {
        case .speechStart:
            .speechStarted
        case .speechEnd:
            .speechEnded
        case nil:
            .probability
        }
    }
}

struct VoiceActivityInferencePipeline {
    private let manager: VadManager
    private let converter = VoiceActivityAudioConverter()
    private var framer = VoiceActivitySampleFramer()
    private var streamState: VadStreamState
    private var previousEndTime: CMTime?

    init(manager: VadManager) async {
        self.manager = manager
        streamState = await manager.makeStreamState()
    }

    init(modelURL: URL) async throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = VadConfig.default.computeUnits
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        manager = VadManager(config: .default, vadModel: model)
        streamState = await manager.makeStreamState()
    }

    mutating func process(
        _ capturedBuffer: CapturedVoiceActivityBuffer
    ) async throws -> [VoiceActivityObservation] {
        previousEndTime = CMTimeAdd(
            capturedBuffer.presentationTime,
            capturedBuffer.duration
        )

        let samples = try converter.convert(capturedBuffer.buffer)
        var observations: [VoiceActivityObservation] = []
        for frame in framer.append(samples) {
            let result = try await manager.processStreamingChunk(frame, state: streamState)
            streamState = result.state
            observations.append(
                VoiceActivityObservation(
                    probability: result.probability,
                    observedAt: Date(),
                    kind: FluidAudioVoiceActivityDetector.observationKind(for: result.event)
                )
            )
        }
        return observations
    }

    func hasDiscontinuity(at presentationTime: CMTime) -> Bool {
        guard let previousEndTime,
              CMTimeCompare(presentationTime, previousEndTime) > 0
        else {
            return false
        }

        return CMTimeGetSeconds(CMTimeSubtract(presentationTime, previousEndTime)) > 0.05
    }

    mutating func reset() async {
        converter.reset()
        framer.reset()
        streamState = await manager.makeStreamState()
        previousEndTime = nil
    }
}

private struct ActiveVoiceActivityDetectionSession: Sendable {
    let id = UUID()
    let capture: VoiceActivityCaptureSession
    let worker: Task<Void, Never>
    let continuation: AsyncStream<VoiceActivityDetectorEvent>.Continuation
}

private final class VoiceActivityCaptureSession: @unchecked Sendable {
    let buffers: AsyncStream<CapturedVoiceActivityBuffer>

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "media.luxel.voice-activity-capture")
    private let bufferQueue: VoiceActivityBufferQueue<CapturedVoiceActivityBuffer>
    private let delegate: VoiceActivitySampleBufferDelegate

    init(deviceID: String?) throws {
        let bufferQueue = VoiceActivityBufferQueue<CapturedVoiceActivityBuffer>()
        self.bufferQueue = bufferQueue
        buffers = bufferQueue.stream
        delegate = VoiceActivitySampleBufferDelegate(bufferQueue: bufferQueue)

        guard let device = Self.captureDevice(deviceID: deviceID) else {
            throw VoiceActivityDetectionFailure.selectedDeviceUnavailable
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw VoiceActivityDetectionFailure.captureUnavailable
        }

        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }

        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VoiceActivityAudioConverter.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]

        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw VoiceActivityDetectionFailure.captureUnavailable
        }

        session.addInput(input)
        output.setSampleBufferDelegate(delegate, queue: queue)
        session.addOutput(output)
    }

    func start() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                session.startRunning()
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                output.setSampleBufferDelegate(nil, queue: nil)
                if session.isRunning {
                    session.stopRunning()
                }
                bufferQueue.finish()
                continuation.resume()
            }
        }
    }

    func takeOverflow() -> Bool {
        delegate.takeOverflow()
    }

    private static func captureDevice(deviceID: String?) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        guard let deviceID, deviceID != AudioInputDeviceID.systemDefault else {
            return AVCaptureDevice.default(for: .audio) ?? discoverySession.devices.first
        }

        return discoverySession.devices.first(where: { $0.uniqueID == deviceID })
    }
}

final class VoiceActivityBufferQueue<Element: Sendable>: @unchecked Sendable {
    static var capacity: Int { 2 }

    let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation

    init() {
        let stream = AsyncStream.makeStream(
            of: Element.self,
            bufferingPolicy: .bufferingNewest(Self.capacity)
        )
        self.stream = stream.stream
        continuation = stream.continuation
    }

    @discardableResult
    func enqueue(_ element: Element) -> Bool {
        if case .dropped = continuation.yield(element) {
            return false
        }
        return true
    }

    func finish() {
        continuation.finish()
    }
}

struct CapturedVoiceActivityBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let presentationTime: CMTime
    let duration: CMTime
}

private final class VoiceActivitySampleBufferDelegate: NSObject,
                                                       AVCaptureAudioDataOutputSampleBufferDelegate,
                                                       @unchecked Sendable {
    private let lock = NSLock()
    private let bufferQueue: VoiceActivityBufferQueue<CapturedVoiceActivityBuffer>
    private var overflowed = false

    init(bufferQueue: VoiceActivityBufferQueue<CapturedVoiceActivityBuffer>) {
        self.bufferQueue = bufferQueue
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        do {
            let buffer = try VoiceActivityAudioConverter.copyBuffer(from: sampleBuffer)
            let wasEnqueued = bufferQueue.enqueue(
                CapturedVoiceActivityBuffer(
                    buffer: buffer,
                    presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                    duration: CMSampleBufferGetDuration(sampleBuffer)
                )
            )
            if !wasEnqueued {
                lock.withLock {
                    overflowed = true
                }
            }
        } catch {
            lock.withLock {
                overflowed = true
            }
        }
    }

    func takeOverflow() -> Bool {
        lock.withLock {
            let value = overflowed
            overflowed = false
            return value
        }
    }
}
