public protocol SystemActivityMonitor: Sendable {
    var currentPauseReasons: Set<ReplayBufferPauseReason> { get }

    func events() -> AsyncStream<SystemActivityEvent>
}

public enum SystemActivityEvent: Equatable, Sendable {
    case pauseReasonBecameActive(ReplayBufferPauseReason)
    case pauseReasonBecameInactive(ReplayBufferPauseReason)
    case displayConfigurationChanged
}
