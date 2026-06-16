import Foundation

public enum RecordingSessionPresentationState: Equatable, Sendable {
    case idle
    case starting
    case countingDown(remaining: TimeInterval)
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
        let content = Self.content(
            state: state,
            canStartRecording: canStartRecording,
            timing: RecordingSessionTiming(state: state, showsMenuBarTime: showElapsedTimeInMenuBar)
        )

        menuBarTitle = content.menuBarTitle
        menuBarSystemImage = content.menuBarSystemImage
        animatesMenuBarSystemImage = content.animatesMenuBarSystemImage
        accessibilityLabel = content.accessibilityLabel
        primaryActionTitle = content.primaryActionTitle
        primaryActionSystemImage = content.primaryActionSystemImage
        canUsePrimaryAction = content.canUsePrimaryAction
        secondaryActionTitle = content.secondaryActionTitle
        secondaryActionSystemImage = content.secondaryActionSystemImage
        canUseSecondaryAction = content.canUseSecondaryAction
        statusMessage = content.statusMessage
    }

    private static func content(
        state: RecordingSessionPresentationState,
        canStartRecording: Bool,
        timing: RecordingSessionTiming
    ) -> RecordingSessionPresentationContent {
        switch state {
        case .idle:
            return idleContent(canStartRecording: canStartRecording)
        case .starting:
            return startingContent()
        case .countingDown(let remaining):
            return countingDownContent(remaining: remaining)
        case .recording:
            return recordingContent(timing: timing)
        case .pausing:
            return pausingContent(timing: timing)
        case .paused:
            return pausedContent(timing: timing)
        case .resuming:
            return resumingContent(timing: timing)
        case .stopping:
            return stoppingContent()
        case .exporting(let snapshot):
            return exportingContent(snapshot: snapshot)
        case .failed(let message):
            return failedContent(message: message, canStartRecording: canStartRecording)
        }
    }

    private static func idleContent(canStartRecording: Bool) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: "Luxel",
            menuBarSystemImage: "record.circle",
            accessibilityLabel: "Luxel",
            primaryActionTitle: "Record",
            primaryActionSystemImage: "record.circle.fill",
            canUsePrimaryAction: canStartRecording
        )
    }

    private static func startingContent() -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: "Starting",
            menuBarSystemImage: "record.circle",
            accessibilityLabel: "Luxel starting recording",
            primaryActionTitle: "Starting",
            primaryActionSystemImage: "record.circle.fill",
            statusMessage: "Starting recording"
        )
    }

    private static func countingDownContent(remaining: TimeInterval) -> RecordingSessionPresentationContent {
        let countdownText = Self.countdownText(remaining)
        return RecordingSessionPresentationContent(
            menuBarTitle: Self.countdownMenuBarText(remaining),
            menuBarSystemImage: "",
            accessibilityLabel: "Luxel recording starts in \(countdownText)",
            primaryActionTitle: "Cancel",
            primaryActionSystemImage: "xmark.circle.fill",
            canUsePrimaryAction: true,
            statusMessage: "Recording starts in \(countdownText)"
        )
    }

    private static func recordingContent(timing: RecordingSessionTiming) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: ""),
            menuBarSystemImage: "record.circle",
            animatesMenuBarSystemImage: true,
            accessibilityLabel: timing.accessibilityLabel(prefix: "Luxel recording"),
            primaryActionTitle: "Stop",
            primaryActionSystemImage: "stop.circle.fill",
            canUsePrimaryAction: true,
            secondaryActionTitle: "Pause",
            secondaryActionSystemImage: "pause.circle",
            canUseSecondaryAction: true,
            statusMessage: "Recording"
        )
    }

    private static func pausingContent(timing: RecordingSessionTiming) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: "●"),
            menuBarSystemImage: "pause.circle",
            accessibilityLabel: "Luxel pausing recording",
            primaryActionTitle: "Stop",
            primaryActionSystemImage: "stop.circle.fill",
            secondaryActionTitle: "Pausing",
            secondaryActionSystemImage: "pause.circle",
            statusMessage: "Pausing recording"
        )
    }

    private static func pausedContent(timing: RecordingSessionTiming) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: ""),
            menuBarSystemImage: "pause.circle.fill",
            accessibilityLabel: timing.pausedAccessibilityLabel,
            primaryActionTitle: "Stop",
            primaryActionSystemImage: "stop.circle.fill",
            canUsePrimaryAction: true,
            secondaryActionTitle: "Resume",
            secondaryActionSystemImage: "play.circle",
            canUseSecondaryAction: true,
            statusMessage: "Paused"
        )
    }

    private static func resumingContent(timing: RecordingSessionTiming) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: "‖"),
            menuBarSystemImage: "play.circle",
            accessibilityLabel: "Luxel resuming recording",
            primaryActionTitle: "Stop",
            primaryActionSystemImage: "stop.circle.fill",
            secondaryActionTitle: "Resuming",
            secondaryActionSystemImage: "play.circle",
            statusMessage: "Resuming recording"
        )
    }

    private static func stoppingContent() -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: "Stopping",
            menuBarSystemImage: "stop.circle.fill",
            accessibilityLabel: "Luxel stopping recording",
            primaryActionTitle: "Stopping",
            primaryActionSystemImage: "stop.circle.fill",
            statusMessage: "Finishing recording"
        )
    }

    private static func exportingContent(snapshot: ExportProgressSnapshot) -> RecordingSessionPresentationContent {
        let progress = Int((snapshot.progress * 100).rounded())
        return RecordingSessionPresentationContent(
            menuBarTitle: "\(progress)%",
            menuBarSystemImage: "square.and.arrow.up",
            accessibilityLabel: "Luxel exporting, \(progress)% complete",
            primaryActionTitle: "Exporting",
            primaryActionSystemImage: "square.and.arrow.up",
            statusMessage: snapshot.actionTitle
        )
    }

    private static func failedContent(
        message: String,
        canStartRecording: Bool
    ) -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: "Luxel",
            menuBarSystemImage: "exclamationmark.triangle.fill",
            accessibilityLabel: "Luxel recording failed",
            primaryActionTitle: "Record",
            primaryActionSystemImage: "record.circle.fill",
            canUsePrimaryAction: canStartRecording,
            statusMessage: message
        )
    }

    fileprivate static func elapsedTimeText(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }

        return "\(minutes):\(twoDigits(seconds))"
    }

    private static func countdownText(_ remaining: TimeInterval) -> String {
        "\(max(0, Int(remaining.rounded(.up)))) s"
    }

    private static func countdownMenuBarText(_ remaining: TimeInterval) -> String {
        "\(max(0, Int(remaining.rounded(.up))))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

private struct RecordingSessionPresentationContent {
    let menuBarTitle: String
    let menuBarSystemImage: String
    var animatesMenuBarSystemImage = false
    let accessibilityLabel: String
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    var canUsePrimaryAction = false
    var secondaryActionTitle: String?
    var secondaryActionSystemImage: String?
    var canUseSecondaryAction = false
    var statusMessage: String?
}

private struct RecordingSessionTiming {
    let elapsedText: String?
    let remainingText: String?
    let displaysTimerTime: Bool
    let displaysElapsedTime: Bool

    init(state: RecordingSessionPresentationState, showsMenuBarTime: Bool) {
        elapsedText = state.elapsed.map(RecordingSessionPresentation.elapsedTimeText)
        remainingText = state.remaining.map(RecordingSessionPresentation.elapsedTimeText)
        displaysTimerTime = showsMenuBarTime && remainingText != nil
        displaysElapsedTime = showsMenuBarTime && elapsedText != nil && !displaysTimerTime
    }

    func menuBarTitle(prefix: String) -> String {
        let text = if displaysTimerTime {
            remainingText.map { "−\($0)" } ?? "−0:00"
        } else {
            displaysElapsedTime ? (elapsedText ?? "0:00") : ""
        }

        guard !prefix.isEmpty else {
            return text
        }

        return text.isEmpty ? prefix : "\(prefix) \(text)"
    }

    func accessibilityLabel(prefix: String) -> String {
        if displaysTimerTime {
            "\(prefix), remaining \(remainingText ?? "0:00")"
        } else if displaysElapsedTime {
            "\(prefix), elapsed \(elapsedText ?? "0:00")"
        } else {
            prefix
        }
    }

    var pausedAccessibilityLabel: String {
        if displaysTimerTime {
            "Luxel recording paused, remaining \(remainingText ?? "0:00")"
        } else if displaysElapsedTime {
            "Luxel recording paused at \(elapsedText ?? "0:00")"
        } else {
            "Luxel recording paused"
        }
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
        case .idle, .starting, .countingDown, .stopping, .exporting, .failed:
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
        case .idle, .starting, .countingDown, .stopping, .exporting, .failed:
            nil
        }
    }
}
