import Foundation

public struct ReplayBufferMenuPresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let statusText: String
    public let statusDetail: String
    public let clipActionTitle: String
    public let pauseActionTitle: String
    public let canClip: Bool
    public let canPause: Bool
    public let pauseActionIsResume: Bool

    public init(
        configuration: ReplayBufferConfiguration?,
        state: ReplayBufferState = .disarmed,
        now: Date = Date()
    ) {
        guard let configuration else {
            self = .hidden
            return
        }
        self = Self.presentation(configuration: configuration, state: state, now: now)
    }

    private init(
        isVisible: Bool,
        statusText: String,
        statusDetail: String,
        clipActionTitle: String,
        pauseActionTitle: String,
        canClip: Bool,
        canPause: Bool,
        pauseActionIsResume: Bool
    ) {
        self.isVisible = isVisible
        self.statusText = statusText
        self.statusDetail = statusDetail
        self.clipActionTitle = clipActionTitle
        self.pauseActionTitle = pauseActionTitle
        self.canClip = canClip
        self.canPause = canPause
        self.pauseActionIsResume = pauseActionIsResume
    }

    private static var hidden: Self {
        Self(
            isVisible: false,
            statusText: LuxelLocalization.string(
                "replayBuffer.status.off",
                defaultValue: "Replay Buffer Off"),
            statusDetail: LuxelLocalization.string(
                "replayBuffer.detail.enableInSettings",
                defaultValue: "Enable in Settings"),
            clipActionTitle: LuxelLocalization.string(
                "replayBuffer.action.clip",
                defaultValue: "Clip Replay Buffer"),
            pauseActionTitle: LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer"),
            canClip: false,
            canPause: false,
            pauseActionIsResume: false
        )
    }

    private static func presentation(
        configuration: ReplayBufferConfiguration,
        state: ReplayBufferState,
        now: Date
    ) -> Self {
        let durationText = durationText(configuration.bufferLength)
        switch state {
        case .disarmed:
            return standardPresentation(
                statusKey: "replayBuffer.status.ready",
                statusDefault: "Replay Buffer Ready",
                configuration: configuration,
                durationText: durationText
            )
        case .starting(let since):
            return bufferingPresentation(
                configuration: configuration,
                durationText: durationText,
                since: since,
                now: now,
                isReady: false
            )
        case .buffering(let since):
            return bufferingPresentation(
                configuration: configuration,
                durationText: durationText,
                since: since,
                now: now,
                isReady: true
            )
        case .paused(let reason):
            return pausedPresentation(reason: reason, durationText: durationText)
        case .clipping:
            return standardPresentation(
                statusKey: "replayBuffer.status.clipping",
                statusDefault: "Clipping Replay Buffer",
                configuration: configuration,
                durationText: durationText
            )
        }
    }

    private static func standardPresentation(
        statusKey: String,
        statusDefault: String,
        configuration: ReplayBufferConfiguration,
        durationText: String
    ) -> Self {
        Self(
            isVisible: true,
            statusText: LuxelLocalization.string(statusKey, defaultValue: statusDefault),
            statusDetail: LuxelLocalization.format(
                "replayBuffer.detail.durationFPS",
                defaultValue: "%@ · %d FPS",
                durationText,
                configuration.frameRate.framesPerSecond
            ),
            clipActionTitle: clipActionTitle(durationText),
            pauseActionTitle: pauseActionTitle,
            canClip: false,
            canPause: false,
            pauseActionIsResume: false
        )
    }

    private static func bufferingPresentation(
        configuration: ReplayBufferConfiguration,
        durationText: String,
        since: Date,
        now: Date,
        isReady: Bool
    ) -> Self {
        Self(
            isVisible: true,
            statusText: LuxelLocalization.string(
                "replayBuffer.status.buffering",
                defaultValue: "Replay Buffering"
            ),
            statusDetail: LuxelLocalization.format(
                "replayBuffer.detail.buffering",
                defaultValue: "Buffering for %@ · %@ · %d FPS",
                elapsedText(from: since, to: now),
                durationText,
                configuration.frameRate.framesPerSecond
            ),
            clipActionTitle: clipActionTitle(durationText),
            pauseActionTitle: pauseActionTitle,
            canClip: isReady,
            canPause: isReady,
            pauseActionIsResume: false
        )
    }

    private static func pausedPresentation(
        reason: ReplayBufferPauseReason,
        durationText: String
    ) -> Self {
        Self(
            isVisible: true,
            statusText: LuxelLocalization.string(
                "replayBuffer.status.paused",
                defaultValue: "Replay Buffer Paused"
            ),
            statusDetail: LuxelLocalization.format(
                "replayBuffer.detail.paused",
                defaultValue: "%@ · %@ buffer",
                pauseReasonText(reason),
                durationText
            ),
            clipActionTitle: clipActionTitle(durationText),
            pauseActionTitle: LuxelLocalization.string(
                "replayBuffer.action.resume",
                defaultValue: "Resume Replay Buffer"
            ),
            canClip: false,
            canPause: reason == .user,
            pauseActionIsResume: true
        )
    }

    private static func clipActionTitle(_ durationText: String) -> String {
        LuxelLocalization.format(
            "replayBuffer.action.clipLast",
            defaultValue: "Clip Last %@",
            durationText
        )
    }

    private static var pauseActionTitle: String {
        LuxelLocalization.string(
            "replayBuffer.action.pause",
            defaultValue: "Pause Replay Buffer"
        )
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(seconds.rounded())
        guard roundedSeconds >= 60, roundedSeconds.isMultiple(of: 60) else {
            return LuxelLocalization.format(
                "replayBuffer.duration.seconds",
                defaultValue: "%d Seconds",
                roundedSeconds)
        }

        let minutes = roundedSeconds / 60
        return minutes == 1
            ? LuxelLocalization.string("replayBuffer.duration.oneMinute", defaultValue: "1 Minute")
            : LuxelLocalization.format(
                "replayBuffer.duration.minutes",
                defaultValue: "%d Minutes",
                minutes)
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let elapsedSeconds = max(0, Int(end.timeIntervalSince(start).rounded(.down)))
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    private static func pauseReasonText(_ reason: ReplayBufferPauseReason) -> String {
        switch reason {
        case .user:
            LuxelLocalization.string("replayBuffer.pause.user", defaultValue: "Paused by You")
        case .recordingActive:
            LuxelLocalization.string(
                "replayBuffer.pause.recordingActive", defaultValue: "Recording Active")
        case .displaySleep:
            LuxelLocalization.string("replayBuffer.pause.displaySleep", defaultValue: "Display Sleep")
        case .locked:
            LuxelLocalization.string("replayBuffer.pause.locked", defaultValue: "Mac Locked")
        case .battery:
            LuxelLocalization.string("replayBuffer.pause.battery", defaultValue: "On Battery")
        case .displayChanged:
            LuxelLocalization.string("replayBuffer.pause.displayChanged", defaultValue: "Display Changed")
        }
    }
}
