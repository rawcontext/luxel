import Foundation

public struct ReplayBufferMenuPresentation: Equatable, Sendable {
    public let isVisible: Bool
    public let statusText: String
    public let statusDetail: String
    public let clipActionTitle: String
    public let pauseActionTitle: String
    public let canClip: Bool
    public let canPause: Bool

    public init(
        configuration: ReplayBufferConfiguration?,
        engineAvailable: Bool = false
    ) {
        guard let configuration else {
            isVisible = false
            statusText = LuxelLocalization.string(
                "replayBuffer.status.off",
                defaultValue: "Replay Buffer Off")
            statusDetail = LuxelLocalization.string(
                "replayBuffer.detail.enableInSettings",
                defaultValue: "Enable in Settings")
            clipActionTitle = LuxelLocalization.string(
                "replayBuffer.action.clip",
                defaultValue: "Clip Replay Buffer")
            pauseActionTitle = LuxelLocalization.string(
                "replayBuffer.action.pause",
                defaultValue: "Pause Replay Buffer")
            canClip = false
            canPause = false
            return
        }

        let durationText = Self.durationText(configuration.bufferLength)
        isVisible = true
        statusText =
            engineAvailable
            ? LuxelLocalization.string(
                "replayBuffer.status.ready",
                defaultValue: "Replay Buffer Ready")
            : LuxelLocalization.string(
                "replayBuffer.status.engineComingSoon",
                defaultValue: "Replay Buffer Engine Coming Soon")
        statusDetail = LuxelLocalization.format(
            "replayBuffer.detail.durationFPS",
            defaultValue: "%@ · %d FPS",
            durationText,
            configuration.frameRate.framesPerSecond)
        clipActionTitle = LuxelLocalization.format(
            "replayBuffer.action.clipLast",
            defaultValue: "Clip Last %@",
            durationText)
        pauseActionTitle = LuxelLocalization.string(
            "replayBuffer.action.pause",
            defaultValue: "Pause Replay Buffer")
        canClip = engineAvailable
        canPause = engineAvailable
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
}
