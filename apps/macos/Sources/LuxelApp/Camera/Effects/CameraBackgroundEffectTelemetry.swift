import CoreMedia
import Foundation
import LuxelCore
import OSLog

final class CameraBackgroundEffectTelemetry: @unchecked Sendable {
    private struct State {
        var processedFrameCount = 0
        var presentedFrameCount = 0
        var renderDropCount = 0
        var processingMilliseconds = 0.0
        var latencySamples: [Double] = []
        var isStopped = false
    }

    private let effect: CameraBackgroundEffect
    private let startedAt = ContinuousClock.now
    private let lock = NSLock()
    private var state = State()

    init(effect: CameraBackgroundEffect) {
        self.effect = effect
    }

    func measureProcessing<T>(_ operation: () throws -> T) rethrows -> T {
        let startedAt = ContinuousClock.now
        let interval = Self.signposter.beginInterval("Camera background frame")
        defer {
            Self.signposter.endInterval("Camera background frame", interval)
            let elapsed = startedAt.duration(to: .now).cameraMilliseconds
            lock.withLock {
                state.processedFrameCount += 1
                state.processingMilliseconds += elapsed
            }
        }
        return try operation()
    }

    func recordRenderDrop() {
        lock.withLock {
            state.renderDropCount += 1
        }
    }

    func recordPresentation(sourceTimestamp: CMTime) {
        guard sourceTimestamp.isValid else {
            return
        }
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        let latencyMilliseconds = CMTimeSubtract(hostTime, sourceTimestamp).seconds * 1_000
        guard latencyMilliseconds.isFinite, latencyMilliseconds >= 0 else {
            return
        }
        lock.withLock {
            state.presentedFrameCount += 1
            state.latencySamples.append(latencyMilliseconds)
            if state.latencySamples.count > Self.maximumLatencySampleCount {
                state.latencySamples.removeFirst()
            }
        }
    }

    func stop(droppedFrameCount: Int) {
        let snapshot: State? = lock.withLock {
            guard !state.isStopped else {
                return nil
            }
            state.isStopped = true
            return state
        }
        guard let snapshot else {
            return
        }

        let sortedLatencies = snapshot.latencySamples.sorted()
        let p95Index = max(0, Int(Double(max(0, sortedLatencies.count - 1)) * 0.95))
        let p95Latency = sortedLatencies.isEmpty ? 0 : sortedLatencies[p95Index]
        let maximumLatency = sortedLatencies.last ?? 0
        let averageProcessing =
            snapshot.processedFrameCount == 0
            ? 0
            : snapshot.processingMilliseconds / Double(snapshot.processedFrameCount)
        let sessionMilliseconds = startedAt.duration(to: .now).cameraMilliseconds

        Self.logger.info(
            """
            Camera background session completed effect=\(self.effect.rawValue, privacy: .public) \
            session_ms=\(sessionMilliseconds, privacy: .public) \
            processed=\(snapshot.processedFrameCount, privacy: .public) \
            presented=\(snapshot.presentedFrameCount, privacy: .public) \
            scheduler_drops=\(droppedFrameCount, privacy: .public) \
            render_drops=\(snapshot.renderDropCount, privacy: .public) \
            average_processing_ms=\(averageProcessing, privacy: .public) \
            p95_capture_to_display_ms=\(p95Latency, privacy: .public) \
            maximum_capture_to_display_ms=\(maximumLatency, privacy: .public) \
            met_150ms_budget=\(p95Latency <= Self.latencyBudgetMilliseconds, privacy: .public)
            """
        )
    }

    private static let maximumLatencySampleCount = 120
    private static let latencyBudgetMilliseconds = 150.0
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.rawcontext.luxel",
        category: "CameraBackgroundEffect"
    )
    private static let signposter = OSSignposter(logger: logger)
}

extension Duration {
    fileprivate var cameraMilliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
