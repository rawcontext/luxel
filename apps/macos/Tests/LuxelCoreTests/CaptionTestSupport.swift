import Foundation
import LuxelCore

func captionCue(
    start: TimeInterval,
    end: TimeInterval,
    text: String
) throws -> CaptionCue {
    try CaptionCue(timeRange: TimeRange(start: start, end: end), text: text)
}

func sampleCaptionTrack() throws -> CaptionTrack {
    try CaptionTrack(
        cues: [
            captionCue(start: 1.2, end: 3.4, text: "Hello\nworld"),
            captionCue(start: 3_661.005, end: 3_662.5, text: "Done")
        ],
        language: Locale.LanguageCode("en"),
        sourceTrack: .microphone
    )
}
