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

        let durationText = Self.durationText(configuration.bufferLength)
        isVisible = true
        clipActionTitle = LuxelLocalization.format(
            "replayBuffer.action.clipLast",
            defaultValue: "Clip Last %@",
            durationText)

        switch state {
        case .disarmed:
            statusText = LuxelLocalization.string(
                "replayBuffer.status.ready",
                defaultValue: "Replay Buffer Ready")
            statusDetail = LuxelLocalization.format(
                "replayBuffer.detail.durationFPS",
                defaultValue: "%@ · %d FPS",
                durationText,
                configuration.frameRate.framesPerSecond)
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer")
            canClip = false
            canPause = false
            pauseActionIsResume = false

        case .starting(let since):
            statusText = LuxelLocalization.string(
                "replayBuffer.status.buffering",
                defaultValue: "Replay Buffering")
            statusDetail = LuxelLocalization.format(
                "replayBuffer.detail.buffering",
                defaultValue: "Buffering for %@ · %@ · %d FPS",
                Self.elapsedText(from: since, to: now),
                durationText,
                configuration.frameRate.framesPerSecond)
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer")
            canClip = false
            canPause = false
            pauseActionIsResume = false

        case .buffering(let since):
            statusText = LuxelLocalization.string(
                "replayBuffer.status.buffering",
                defaultValue: "Replay Buffering")
            statusDetail = LuxelLocalization.format(
                "replayBuffer.detail.buffering",
                defaultValue: "Buffering for %@ · %@ · %d FPS",
                Self.elapsedText(from: since, to: now),
                durationText,
                configuration.frameRate.framesPerSecond)
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer")
            canClip = true
            canPause = true
            pauseActionIsResume = false

        case .paused(let reason):
            statusText = LuxelLocalization.string(
                "replayBuffer.status.paused",
                defaultValue: "Replay Buffer Paused")
            statusDetail = LuxelLocalization.format(
                "replayBuffer.detail.paused",
                defaultValue: "%@ · %@ buffer",
                Self.pauseReasonText(reason),
                durationText)
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.resume",
                defaultValue: "Resume Replay Buffer")
            canClip = false
            canPause = reason == .user
            pauseActionIsResume = true

        case .clipping:
            statusText = LuxelLocalization.string(
                "replayBuffer.status.clipping",
                defaultValue: "Clipping Replay Buffer")
            statusDetail = LuxelLocalization.format(
                "replayBuffer.detail.durationFPS",
                defaultValue: "%@ · %d FPS",
                durationText,
                configuration.frameRate.framesPerSecond)
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer")
            canClip = false
            canPause = false
            pauseActionIsResume = false
        }
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
