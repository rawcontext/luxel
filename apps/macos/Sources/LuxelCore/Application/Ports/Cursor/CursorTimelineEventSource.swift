import Foundation

public enum CursorTimelineSourceEvent: Equatable, Sendable {
    case sample(wallTime: TimeInterval, position: CursorPoint, cursorImage: CursorImageAsset)
    case click(wallTime: TimeInterval, button: CursorClickButton, phase: CursorClickPhase)
    case spotlightToggle(wallTime: TimeInterval)
}

public protocol CursorTimelineEventSource: Sendable {
    func events() -> AsyncStream<CursorTimelineSourceEvent>
}
