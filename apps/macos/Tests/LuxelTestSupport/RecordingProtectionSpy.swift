import Foundation
import LuxelCore

public final class RecordingProtectionSpy: RecordingTerminationProtection, @unchecked Sendable {
    public enum Event: Equatable, Sendable {
        case recordingWillStart
        case recordingDidEnd
    }

    private let lock = NSLock()
    private var recordedEvents: [Event] = []

    public init() {}

    public var events: [Event] {
        lock.withLock {
            recordedEvents
        }
    }

    public func recordingWillStart() {
        lock.withLock {
            recordedEvents.append(.recordingWillStart)
        }
    }

    public func recordingDidEnd() {
        lock.withLock {
            recordedEvents.append(.recordingDidEnd)
        }
    }
}
