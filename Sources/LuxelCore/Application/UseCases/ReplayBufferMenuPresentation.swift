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
            statusText = "Replay Buffer Off"
            statusDetail = "Enable in Settings"
            clipActionTitle = "Clip Replay Buffer"
            pauseActionTitle = "Pause Replay Buffer"
            canClip = false
            canPause = false
            return
        }

        let durationText = Self.durationText(configuration.bufferLength)
        isVisible = true
        statusText = engineAvailable ? "Replay Buffer Ready" : "Replay Buffer Engine Coming Soon"
        statusDetail = "\(durationText) · \(configuration.frameRate.framesPerSecond) FPS"
        clipActionTitle = "Clip Last \(durationText)"
        pauseActionTitle = "Pause Replay Buffer"
        canClip = engineAvailable
        canPause = engineAvailable
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let roundedSeconds = Int(seconds.rounded())
        guard roundedSeconds >= 60, roundedSeconds.isMultiple(of: 60) else {
            return "\(roundedSeconds) Seconds"
        }

        let minutes = roundedSeconds / 60
        return minutes == 1 ? "1 Minute" : "\(minutes) Minutes"
    }
}
