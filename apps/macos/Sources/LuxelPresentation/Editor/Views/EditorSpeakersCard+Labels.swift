import Foundation
import LuxelCore

extension EditorSpeakersCard {
    func voiceStats(_ voice: DetectedSpeakerVoice) -> String {
        let turns =
            voice.turnCount == 1
            ? LuxelLocalization.string("1 turn")
            : LuxelLocalization.format("%d turns", voice.turnCount)
        return "\(formatDuration(voice.totalSpeakingTime)) · \(turns)"
    }
    func speakerCountLabel(_ count: Int) -> String {
        count == 1 ? LuxelLocalization.string("1 speaker") : LuxelLocalization.format("%d speakers", count)
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
