import Foundation
import LuxelCore
import OSLog

@MainActor
struct RecordingStartLatencySpan {
    let entryPoint: RecordingStartEntryPoint
    let target: CaptureTarget?
    let startedAt: ContinuousClock.Instant
    let intervalState: OSSignpostIntervalState
}

@MainActor
enum LuxelRecordingLatencyTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "media.luxel.app",
        category: "RecordingLatency"
    )
    private static let signposter = OSSignposter(logger: logger)
    private static let clock = ContinuousClock()
    private static let budgetMilliseconds: Int64 = 1_000

    static func begin(
        entryPoint: RecordingStartEntryPoint,
        target: CaptureTarget? = nil
    ) -> RecordingStartLatencySpan {
        let signpostID = signposter.makeSignpostID()
        let intervalState = signposter.beginInterval("Recording start", id: signpostID)

        logger.info("Recording start requested entry_point=\(entryPoint.rawValue, privacy: .public)")

        return RecordingStartLatencySpan(
            entryPoint: entryPoint,
            target: target,
            startedAt: clock.now,
            intervalState: intervalState
        )
    }

    static func finishStarted(_ span: RecordingStartLatencySpan, target: CaptureTarget? = nil) {
        finish(span, result: "started", target: target ?? span.target)
    }

    static func finishFailed(_ span: RecordingStartLatencySpan, reason: String) {
        finish(span, result: "failed:\(reason)", target: span.target)
    }

    private static func finish(
        _ span: RecordingStartLatencySpan,
        result: String,
        target: CaptureTarget?
    ) {
        let elapsedMilliseconds = span.startedAt.duration(to: clock.now).wholeMilliseconds
        let metBudget = elapsedMilliseconds <= budgetMilliseconds

        logger.info(
            """
      Recording start completed entry_point=\(span.entryPoint.rawValue, privacy: .public) \
      result=\(result, privacy: .public) \
      target_kind=\(target?.latencyTargetKind ?? "unknown", privacy: .public) \
      elapsed_ms=\(elapsedMilliseconds, privacy: .public) \
      budget_ms=\(budgetMilliseconds, privacy: .public) \
      met_budget=\(metBudget, privacy: .public)
      """
        )
        signposter.endInterval("Recording start", span.intervalState)
    }
}

extension CaptureTarget {
    fileprivate var latencyTargetKind: String {
        switch self {
        case .display:
            "display"
        case .window:
            "window"
        case .area:
            "area"
        }
    }
}

extension Duration {
    fileprivate var wholeMilliseconds: Int64 {
        let durationComponents = components
        return durationComponents.seconds * 1_000
            + durationComponents.attoseconds / 1_000_000_000_000_000
    }
}
