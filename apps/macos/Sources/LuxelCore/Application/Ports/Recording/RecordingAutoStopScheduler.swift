import Foundation

public protocol RecordingAutoStopTask: Sendable {
    func cancel()
}

public protocol RecordingAutoStopScheduler: Sendable {
    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) -> any RecordingAutoStopTask
}

public struct TaskRecordingAutoStopScheduler: RecordingAutoStopScheduler {
    public init() {}

    public func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) -> any RecordingAutoStopTask {
        TaskRecordingAutoStopTask(interval: max(0, interval), operation: operation)
    }
}

private final class TaskRecordingAutoStopTask: RecordingAutoStopTask, @unchecked Sendable {
    private let state: TaskRecordingAutoStopTaskState
    private let task: Task<Void, Never>

    init(interval: TimeInterval, operation: @escaping @Sendable () async -> Void) {
        let state = TaskRecordingAutoStopTaskState()
        self.state = state
        task = Task {
            do {
                try await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, state.startOperationIfNotCanceled() else {
                    return
                }

                await operation()
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    func cancel() {
        guard state.cancelBeforeOperationStarts() else {
            return
        }

        task.cancel()
    }
}

private final class TaskRecordingAutoStopTaskState: @unchecked Sendable {
    private let lock = NSLock()
    private var didCancel = false
    private var didStartOperation = false

    func startOperationIfNotCanceled() -> Bool {
        lock.withLock {
            guard !didCancel else {
                return false
            }

            didStartOperation = true
            return true
        }
    }

    func cancelBeforeOperationStarts() -> Bool {
        lock.withLock {
            guard !didStartOperation else {
                return false
            }

            didCancel = true
            return true
        }
    }
}
