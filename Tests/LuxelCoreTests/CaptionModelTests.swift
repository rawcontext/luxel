import Foundation
import LuxelCore
import Testing

@Suite("Caption models")
struct CaptionModelTests {
    @Test("cue validates text and preserves two-line captions")
    func cueValidatesTextAndPreservesTwoLineCaptions() throws {
        let cue = try CaptionCue(
            timeRange: TimeRange(start: 1, end: 2),
            text: "  Hello\nworld  "
        )

        #expect(cue.text == "Hello\nworld")

        #expect(throws: CaptionModelError.invalidCueText) {
            _ = try CaptionCue(timeRange: TimeRange(start: 0, end: 1), text: "   ")
        }
        #expect(throws: CaptionModelError.tooManyCueLines) {
            _ = try CaptionCue(timeRange: TimeRange(start: 0, end: 1), text: "one\ntwo\nthree")
        }
        #expect(throws: CaptionModelError.tooManyCueLines) {
            _ = try CaptionCue(timeRange: TimeRange(start: 0, end: 1), text: "one\n\nthree")
        }
    }

    @Test("track validates sorted non-overlapping cues")
    func trackValidatesSortedNonOverlappingCues() throws {
        let first = try cue(start: 0, end: 1, text: "First")
        let second = try cue(start: 1, end: 2, text: "Second")
        let overlapping = try cue(start: 0.5, end: 1.5, text: "Overlap")

        let track = try CaptionTrack(
            cues: [first, second],
            language: Locale.LanguageCode("en"),
            sourceTrack: .microphone
        )

        #expect(track.cues == [first, second])
        #expect(track.language == Locale.LanguageCode("en"))
        #expect(track.sourceTrack == .microphone)

        #expect(throws: CaptionModelError.unsortedCues) {
            _ = try CaptionTrack(cues: [second, first], language: Locale.LanguageCode("en"))
        }
        #expect(throws: CaptionModelError.overlappingCues) {
            _ = try CaptionTrack(cues: [first, overlapping], language: Locale.LanguageCode("en"))
        }
    }

    @Test("render options expose caption defaults")
    func renderOptionsExposeCaptionDefaults() {
        let defaults = CaptionRenderOptions()
        let custom = CaptionRenderOptions(
            burnIn: true,
            position: .top,
            size: .large,
            theme: .highContrast
        )

        #expect(!defaults.burnIn)
        #expect(defaults.position == .lowerThird)
        #expect(defaults.size == .medium)
        #expect(defaults.theme == .darkGlass)
        #expect(custom.burnIn)
        #expect(custom.position == .top)
        #expect(custom.size == .large)
        #expect(custom.theme == .highContrast)
    }

    @Test("SRT serializer emits indexed cues with comma milliseconds")
    func srtSerializerEmitsIndexedCuesWithCommaMilliseconds() throws {
        let track = try sampleTrack()

        let text = SRTCaptionSerializer.serialize(track)

        #expect(text == """
        1
        00:00:01,200 --> 00:00:03,400
        Hello
        world

        2
        01:01:01,005 --> 01:01:02,500
        Done

        """)
    }

    @Test("VTT serializer emits webvtt header and dot milliseconds")
    func vttSerializerEmitsHeaderAndDotMilliseconds() throws {
        let track = try sampleTrack()

        let text = VTTCaptionSerializer.serialize(track)

        #expect(text == """
        WEBVTT

        00:00:01.200 --> 00:00:03.400
        Hello
        world

        01:01:01.005 --> 01:01:02.500
        Done

        """)
    }

    @Test("serializers handle empty tracks")
    func serializersHandleEmptyTracks() throws {
        let track = try CaptionTrack(cues: [], language: Locale.LanguageCode("en"))

        #expect(SRTCaptionSerializer.serialize(track) == "")
        #expect(VTTCaptionSerializer.serialize(track) == "WEBVTT\n")
    }

    private func sampleTrack() throws -> CaptionTrack {
        try CaptionTrack(
            cues: [
                cue(start: 1.2, end: 3.4, text: "Hello\nworld"),
                cue(start: 3_661.005, end: 3_662.5, text: "Done")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .microphone
        )
    }

    private func cue(
        start: TimeInterval,
        end: TimeInterval,
        text: String
    ) throws -> CaptionCue {
        try CaptionCue(timeRange: TimeRange(start: start, end: end), text: text)
    }
}
