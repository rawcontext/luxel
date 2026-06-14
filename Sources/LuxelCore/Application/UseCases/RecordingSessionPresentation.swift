import Foundation

public enum RecordingSessionPresentationState: Equatable, Sendable {
    case idle
    case starting
    case recording(elapsed: TimeInterval, remaining: TimeInterval? = nil)
    case pausing(elapsed: TimeInterval, remaining: TimeInterval? = nil)
    case paused(elapsed: TimeInterval, remaining: TimeInterval? = nil)
    case resuming(elapsed: TimeInterval, remaining: TimeInterval? = nil)
    case stopping
    case exporting(ExportProgressSnapshot)
    case failed(String)
}

public struct RecordingSessionPresentation: Equatable, Sendable {
    public let menuBarTitle: String
    public let menuBarSystemImage: String
    public let alternateMenuBarSystemImage: String?
    public let animatesMenuBarSystemImage: Bool
    public let accessibilityLabel: String
    public let primaryActionTitle: String
    public let primaryActionSystemImage: String
    public let canUsePrimaryAction: Bool
    public let secondaryActionTitle: String?
    public let secondaryActionSystemImage: String?
    public let canUseSecondaryAction: Bool
    public let statusMessage: String?

    public init(
        state: RecordingSessionPresentationState,
        canStartRecording: Bool,
        showElapsedTimeInMenuBar: Bool = true
    ) {
        let elapsed = state.elapsed
        let elapsedText = elapsed.map(Self.elapsedTimeText)
        let remaining = state.remaining
        let remainingText = remaining.map(Self.elapsedTimeText)
        let displaysTimerTime = showElapsedTimeInMenuBar && remainingText != nil
        let displaysElapsedTime = showElapsedTimeInMenuBar && elapsedText != nil && !displaysTimerTime
        let timerMenuText = remainingText.map { "−\($0)" }

        switch state {
        case .idle:
            menuBarTitle = "Luxel"
            menuBarSystemImage = "record.circle"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel"
            primaryActionTitle = "Record"
            primaryActionSystemImage = "record.circle.fill"
            canUsePrimaryAction = canStartRecording
            secondaryActionTitle = nil
            secondaryActionSystemImage = nil
            canUseSecondaryAction = false
            statusMessage = nil
        case .starting:
            menuBarTitle = "Starting"
            menuBarSystemImage = "record.circle"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel starting recording"
            primaryActionTitle = "Starting"
            primaryActionSystemImage = "record.circle.fill"
            canUsePrimaryAction = false
            secondaryActionTitle = nil
            secondaryActionSystemImage = nil
            canUseSecondaryAction = false
            statusMessage = "Starting recording"
        case .recording:
            menuBarTitle = if displaysTimerTime {
                "● \(timerMenuText ?? "−0:00")"
            } else {
                displaysElapsedTime ? "● \(elapsedText ?? "0:00")" : "●"
            }
            menuBarSystemImage = "record.circle.fill"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = true
            accessibilityLabel = if displaysTimerTime {
                "Luxel recording, remaining \(remainingText ?? "0:00")"
            } else if displaysElapsedTime {
                "Luxel recording, elapsed \(elapsedText ?? "0:00")"
            } else {
                "Luxel recording"
            }
            primaryActionTitle = "Stop"
            primaryActionSystemImage = "stop.circle.fill"
            canUsePrimaryAction = true
            secondaryActionTitle = "Pause"
            secondaryActionSystemImage = "pause.circle"
            canUseSecondaryAction = true
            statusMessage = "Recording"
        case .pausing:
            menuBarTitle = if displaysTimerTime {
                "● \(timerMenuText ?? "−0:00")"
            } else {
                displaysElapsedTime ? "● \(elapsedText ?? "0:00")" : "●"
            }
            menuBarSystemImage = "pause.circle"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel pausing recording"
            primaryActionTitle = "Stop"
            primaryActionSystemImage = "stop.circle.fill"
            canUsePrimaryAction = false
            secondaryActionTitle = "Pausing"
            secondaryActionSystemImage = "pause.circle"
            canUseSecondaryAction = false
            statusMessage = "Pausing recording"
        case .paused:
            menuBarTitle = if displaysTimerTime {
                "‖ \(timerMenuText ?? "−0:00")"
            } else {
                displaysElapsedTime ? "‖ \(elapsedText ?? "0:00")" : "‖"
            }
            menuBarSystemImage = "pause.circle.fill"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = if displaysTimerTime {
                "Luxel recording paused, remaining \(remainingText ?? "0:00")"
            } else if displaysElapsedTime {
                "Luxel recording paused at \(elapsedText ?? "0:00")"
            } else {
                "Luxel recording paused"
            }
            primaryActionTitle = "Stop"
            primaryActionSystemImage = "stop.circle.fill"
            canUsePrimaryAction = true
            secondaryActionTitle = "Resume"
            secondaryActionSystemImage = "play.circle"
            canUseSecondaryAction = true
            statusMessage = "Paused"
        case .resuming:
            menuBarTitle = if displaysTimerTime {
                "‖ \(timerMenuText ?? "−0:00")"
            } else {
                displaysElapsedTime ? "‖ \(elapsedText ?? "0:00")" : "‖"
            }
            menuBarSystemImage = "play.circle"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel resuming recording"
            primaryActionTitle = "Stop"
            primaryActionSystemImage = "stop.circle.fill"
            canUsePrimaryAction = false
            secondaryActionTitle = "Resuming"
            secondaryActionSystemImage = "play.circle"
            canUseSecondaryAction = false
            statusMessage = "Resuming recording"
        case .stopping:
            menuBarTitle = "Stopping"
            menuBarSystemImage = "stop.circle.fill"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel stopping recording"
            primaryActionTitle = "Stopping"
            primaryActionSystemImage = "stop.circle.fill"
            canUsePrimaryAction = false
            secondaryActionTitle = nil
            secondaryActionSystemImage = nil
            canUseSecondaryAction = false
            statusMessage = "Finishing recording"
        case .exporting(let snapshot):
            let progress = Int((snapshot.progress * 100).rounded())
            menuBarTitle = "\(progress)%"
            menuBarSystemImage = "square.and.arrow.up"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel exporting, \(progress)% complete"
            primaryActionTitle = "Exporting"
            primaryActionSystemImage = "square.and.arrow.up"
            canUsePrimaryAction = false
            secondaryActionTitle = nil
            secondaryActionSystemImage = nil
            canUseSecondaryAction = false
            statusMessage = snapshot.actionTitle
        case .failed(let message):
            menuBarTitle = "Luxel"
            menuBarSystemImage = "exclamationmark.triangle.fill"
            alternateMenuBarSystemImage = nil
            animatesMenuBarSystemImage = false
            accessibilityLabel = "Luxel recording failed"
            primaryActionTitle = "Record"
            primaryActionSystemImage = "record.circle.fill"
            canUsePrimaryAction = canStartRecording
            secondaryActionTitle = nil
            secondaryActionSystemImage = nil
            canUseSecondaryAction = false
            statusMessage = message
        }
    }

    private static func elapsedTimeText(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }

        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

private extension RecordingSessionPresentationState {
    var elapsed: TimeInterval? {
        switch self {
        case .recording(let elapsed, _),
             .pausing(let elapsed, _),
             .paused(let elapsed, _),
             .resuming(let elapsed, _):
            elapsed
        case .idle, .starting, .stopping, .exporting, .failed:
            nil
        }
    }

    var remaining: TimeInterval? {
        switch self {
        case .recording(_, let remaining),
             .pausing(_, let remaining),
             .paused(_, let remaining),
             .resuming(_, let remaining):
            remaining
        case .idle, .starting, .stopping, .exporting, .failed:
            nil
        }
    }
}
