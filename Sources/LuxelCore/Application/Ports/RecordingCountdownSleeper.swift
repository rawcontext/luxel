import Foundation

public protocol RecordingCountdownSleeper: Sendable {
    func sleep(for duration: TimeInterval) async throws
}

public struct TaskRecordingCountdownSleeper: RecordingCountdownSleeper {
    public init() {}

    public func sleep(for duration: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(duration))
    }
}
