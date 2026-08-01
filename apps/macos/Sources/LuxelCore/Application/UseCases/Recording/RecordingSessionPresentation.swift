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
            primaryActionTitle: LuxelLocalization.string(
                "recording.action.record", defaultValue: "Record"),
            primaryActionSystemImage: "record.circle.fill",
            canUsePrimaryAction: canStartRecording
        )
    }

    private static func startingContent() -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: LuxelLocalization.string("recording.state.starting", defaultValue: "Starting"),
            menuBarSystemImage: "record.circle",
            accessibilityLabel: LuxelLocalization.string(
                "recording.accessibility.starting",
                defaultValue: "Luxel starting recording"),
            primaryActionTitle: LuxelLocalization.string(
                "recording.state.starting", defaultValue: "Starting"),
            primaryActionSystemImage: "record.circle.fill",
            statusMessage: LuxelLocalization.string(
                "recording.status.starting",
                defaultValue: "Starting recording")
        )
    }

    private static func countingDownContent(remaining: TimeInterval)
    -> RecordingSessionPresentationContent {
        let countdownText = Self.countdownText(remaining)
        return RecordingSessionPresentationContent(
            menuBarTitle: Self.countdownMenuBarText(remaining),
            menuBarSystemImage: "",
            accessibilityLabel: LuxelLocalization.format(
                "recording.accessibility.countdown",
                defaultValue: "Luxel recording starts in %@",
                countdownText),
            primaryActionTitle: LuxelLocalization.string("common.cancel", defaultValue: "Cancel"),
            primaryActionSystemImage: "xmark.circle.fill",
            canUsePrimaryAction: true,
            statusMessage: LuxelLocalization.format(
                "recording.status.countdown",
                defaultValue: "Recording starts in %@",
                countdownText)
        )
    }

    private static func recordingContent(timing: RecordingSessionTiming)
    -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: ""),
            menuBarSystemImage: "record.circle",
            animatesMenuBarSystemImage: true,
            accessibilityLabel: timing.accessibilityLabel(
                prefix: LuxelLocalization.string(
                    "recording.accessibility.recording",
                    defaultValue: "Luxel recording")),
            primaryActionTitle: LuxelLocalization.string("recording.action.stop", defaultValue: "Stop"),
            primaryActionSystemImage: "stop.circle.fill",
            canUsePrimaryAction: true,
            secondaryActionTitle: LuxelLocalization.string(
                "recording.action.pause", defaultValue: "Pause"),
            secondaryActionSystemImage: "pause.circle",
            canUseSecondaryAction: true,
            statusMessage: LuxelLocalization.string(
                "recording.state.recording", defaultValue: "Recording")
        )
    }

    private static func pausingContent(timing: RecordingSessionTiming)
    -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: "●"),
            menuBarSystemImage: "pause.circle",
            accessibilityLabel: LuxelLocalization.string(
                "recording.accessibility.pausing",
                defaultValue: "Luxel pausing recording"),
            primaryActionTitle: LuxelLocalization.string("recording.action.stop", defaultValue: "Stop"),
            primaryActionSystemImage: "stop.circle.fill",
            secondaryActionTitle: LuxelLocalization.string(
                "recording.state.pausing", defaultValue: "Pausing"),
            secondaryActionSystemImage: "pause.circle",
            statusMessage: LuxelLocalization.string(
                "recording.status.pausing",
                defaultValue: "Pausing recording")
        )
    }

    private static func pausedContent(timing: RecordingSessionTiming)
    -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: ""),
            menuBarSystemImage: "pause.circle.fill",
            accessibilityLabel: timing.pausedAccessibilityLabel,
            primaryActionTitle: LuxelLocalization.string("recording.action.stop", defaultValue: "Stop"),
            primaryActionSystemImage: "stop.circle.fill",
            canUsePrimaryAction: true,
            secondaryActionTitle: LuxelLocalization.string(
                "recording.action.resume", defaultValue: "Resume"),
            secondaryActionSystemImage: "play.circle",
            canUseSecondaryAction: true,
            statusMessage: LuxelLocalization.string("recording.state.paused", defaultValue: "Paused")
        )
    }

    private static func resumingContent(timing: RecordingSessionTiming)
    -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: timing.menuBarTitle(prefix: "‖"),
            menuBarSystemImage: "play.circle",
            accessibilityLabel: LuxelLocalization.string(
                "recording.accessibility.resuming",
                defaultValue: "Luxel resuming recording"),
            primaryActionTitle: LuxelLocalization.string("recording.action.stop", defaultValue: "Stop"),
            primaryActionSystemImage: "stop.circle.fill",
            secondaryActionTitle: LuxelLocalization.string(
                "recording.state.resuming", defaultValue: "Resuming"),
            secondaryActionSystemImage: "play.circle",
            statusMessage: LuxelLocalization.string(
                "recording.status.resuming",
                defaultValue: "Resuming recording")
        )
    }

    private static func stoppingContent() -> RecordingSessionPresentationContent {
        RecordingSessionPresentationContent(
            menuBarTitle: LuxelLocalization.string("recording.state.stopping", defaultValue: "Stopping"),
            menuBarSystemImage: "stop.circle.fill",
            accessibilityLabel: LuxelLocalization.string(
                "recording.accessibility.stopping",
                defaultValue: "Luxel stopping recording"),
            primaryActionTitle: LuxelLocalization.string(
                "recording.state.stopping", defaultValue: "Stopping"),
            primaryActionSystemImage: "stop.circle.fill",
            statusMessage: LuxelLocalization.string(
                "recording.status.finishing",
                defaultValue: "Finishing recording")
        )
    }

    private static func exportingContent(snapshot: ExportProgressSnapshot)
    -> RecordingSessionPresentationContent {
        let progress = Int((snapshot.progress * 100).rounded())
        return RecordingSessionPresentationContent(
            menuBarTitle: "\(progress)%",
            menuBarSystemImage: "square.and.arrow.up",
            accessibilityLabel: LuxelLocalization.format(
                "recording.accessibility.exporting",
                defaultValue: "Luxel exporting, %d%% complete",
                progress),
            primaryActionTitle: LuxelLocalization.string(
                "recording.state.exporting", defaultValue: "Exporting"),
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
            accessibilityLabel: LuxelLocalization.string(
                "recording.accessibility.failed",
                defaultValue: "Luxel recording failed"),
            primaryActionTitle: LuxelLocalization.string(
                "recording.action.record", defaultValue: "Record"),
            primaryActionSystemImage: "record.circle.fill",
            canUsePrimaryAction: canStartRecording,
            statusMessage: message
        )
    }

    private static func countdownText(_ remaining: TimeInterval) -> String {
        LuxelLocalization.format(
            "recording.countdown.seconds",
            defaultValue: "%d s",
            max(0, Int(remaining.rounded(.up))))
    }

    private static func countdownMenuBarText(_ remaining: TimeInterval) -> String {
        "\(max(0, Int(remaining.rounded(.up))))"
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
        elapsedText = state.elapsed.map(RecordingDurationFormatter.elapsedTime)
        remainingText = state.remaining.map(RecordingDurationFormatter.elapsedTime)
        displaysTimerTime = showsMenuBarTime && remainingText != nil
        displaysElapsedTime = showsMenuBarTime && elapsedText != nil && !displaysTimerTime
    }

    func menuBarTitle(prefix: String) -> String {
        let text =
            if displaysTimerTime {
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
            LuxelLocalization.format(
                "recording.accessibility.remaining",
                defaultValue: "%@, remaining %@",
                prefix,
                remainingText ?? "0:00")
        } else if displaysElapsedTime {
            LuxelLocalization.format(
                "recording.accessibility.elapsed",
                defaultValue: "%@, elapsed %@",
                prefix,
                elapsedText ?? "0:00")
        } else {
            prefix
        }
    }

    var pausedAccessibilityLabel: String {
        if displaysTimerTime {
            LuxelLocalization.format(
                "recording.accessibility.pausedRemaining",
                defaultValue: "Luxel recording paused, remaining %@",
                remainingText ?? "0:00")
        } else if displaysElapsedTime {
            LuxelLocalization.format(
                "recording.accessibility.pausedElapsed",
                defaultValue: "Luxel recording paused at %@",
                elapsedText ?? "0:00")
        } else {
            LuxelLocalization.string(
                "recording.accessibility.paused",
                defaultValue: "Luxel recording paused")
        }
    }
}

extension RecordingSessionPresentationState {
    fileprivate var elapsed: TimeInterval? {
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

    fileprivate var remaining: TimeInterval? {
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
