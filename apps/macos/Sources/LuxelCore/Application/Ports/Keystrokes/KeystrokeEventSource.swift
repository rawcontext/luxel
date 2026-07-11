import Foundation

public enum KeystrokeSourceEvent: Equatable, Sendable {
    case keyDown(
            wallTime: TimeInterval,
            keyCode: Int,
            characters: String?,
            modifiers: Set<KeystrokeModifier>,
            isRepeat: Bool
         )
    case flagsChanged(
            wallTime: TimeInterval,
            keyCode: Int,
            modifiers: Set<KeystrokeModifier>
         )
    case pauseStarted(wallTime: TimeInterval, cause: KeystrokePauseCause)
    case pauseEnded(wallTime: TimeInterval, cause: KeystrokePauseCause)
}

public protocol KeystrokeEventSource: Sendable {
    func events() -> AsyncStream<KeystrokeSourceEvent>
}

public enum KeystrokeCaptureStatus: Equatable, Sendable {
    case idle
    case active
    case paused(KeystrokePauseCause)
    case permissionDenied
    case eventDeliveryRecovered
    case eventDeliveryUnavailable
}

public protocol KeystrokeCaptureEventSource: KeystrokeEventSource {
    var statusUpdates: AsyncStream<KeystrokeCaptureStatus> { get }

    func setUserPaused(_ isPaused: Bool)
    func setRecordingPaused(_ isPaused: Bool)
    func stop()
}
