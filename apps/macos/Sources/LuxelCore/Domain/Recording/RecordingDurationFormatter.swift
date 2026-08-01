import Foundation

public enum RecordingDurationFormatter {
    public static func elapsedTime(_ elapsed: TimeInterval) -> String {
        elapsedTime(elapsed, padsMinutesWhenNoHours: false)
    }

    public static func elapsedTime(
        _ elapsed: TimeInterval,
        padsMinutesWhenNoHours: Bool
    ) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        let minuteText = padsMinutesWhenNoHours ? twoDigits(minutes) : "\(minutes)"
        return "\(minuteText):\(twoDigits(seconds))"
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
