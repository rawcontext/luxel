import Foundation

public final class ProcessInfoRecordingProtection: RecordingTerminationProtection, @unchecked Sendable {
    private let processInfo: ProcessInfo
    private let lock = NSLock()
    private var activity: (any NSObjectProtocol)?
    private var activeRecordingCount = 0

    public init(processInfo: ProcessInfo = .processInfo) {
        self.processInfo = processInfo
    }

    public func recordingWillStart() {
        lock.withLock {
            if activeRecordingCount == 0 {
                activity = processInfo.beginActivity(
                    options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
                    reason: "Luxel is recording media"
                )
            }
            activeRecordingCount += 1
        }
    }

    public func recordingDidEnd() {
        let completedActivity = lock.withLock { () -> (any NSObjectProtocol)? in
            guard activeRecordingCount > 0 else {
                return nil
            }

            activeRecordingCount -= 1
            guard activeRecordingCount == 0 else {
                return nil
            }

            let completedActivity = activity
            activity = nil
            return completedActivity
        }

        if let completedActivity {
            processInfo.endActivity(completedActivity)
        }
    }
}
