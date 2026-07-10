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

    @Test("track editor mutates cues while preserving track metadata")
    func trackEditorMutatesCuesWhilePreservingMetadata() throws {
        let track = try CaptionTrack(
            cues: [
                cue(start: 0, end: 2, text: "First"),
                cue(start: 3, end: 4, text: "Second")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .microphone
        )
        let editor = CaptionTrackEditor(track: track)

        let replaced = try editor.replacingCue(
            at: 1,
            with: cue(start: 3.1, end: 4.2, text: "Updated")
        )
        #expect(replaced.cues.map(\.text) == ["First", "Updated"])
        #expect(replaced.language == track.language)
        #expect(replaced.sourceTrack == track.sourceTrack)

        let split = try editor.splittingCue(
            at: 0,
            splitTime: 1,
            firstText: "First half",
            secondText: "Second half"
        )
        let expectedSplitCues = [
            try cue(start: 0, end: 1, text: "First half"),
            try cue(start: 1, end: 2, text: "Second half"),
            try cue(start: 3, end: 4, text: "Second")
        ]
        #expect(split.cues == expectedSplitCues)

        let merged = try CaptionTrackEditor(track: split).mergingCue(at: 0)
        let expectedMergedCues = [
            try cue(start: 0, end: 2, text: "First half\nSecond half"),
            try cue(start: 3, end: 4, text: "Second")
        ]
        #expect(merged.cues == expectedMergedCues)

        let deleted = try editor.deletingCue(at: 0)
        let expectedDeletedCues = [try cue(start: 3, end: 4, text: "Second")]
        #expect(deleted.cues == expectedDeletedCues)
    }

    @Test("track editor rejects invalid cue mutations")
    func trackEditorRejectsInvalidCueMutations() throws {
        let track = try CaptionTrack(
            cues: [
                cue(start: 0, end: 1, text: "First"),
                cue(start: 2, end: 3, text: "Second")
            ],
            language: Locale.LanguageCode("en")
        )
        let editor = CaptionTrackEditor(track: track)

        #expect(throws: CaptionModelError.invalidCueIndex) {
            _ = try editor.deletingCue(at: 2)
        }
        #expect(throws: CaptionModelError.invalidCueSplitTime) {
            _ = try editor.splittingCue(
                at: 0,
                splitTime: 1,
                firstText: "First",
                secondText: "Second"
            )
        }
        #expect(throws: CaptionModelError.overlappingCues) {
            _ = try editor.replacingCue(
                at: 1,
                with: cue(start: 0.5, end: 2.5, text: "Overlap")
            )
        }
        #expect(throws: CaptionModelError.invalidCueIndex) {
            _ = try editor.mergingCue(at: 1)
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

        #expect(
            text == """
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

        #expect(
            text == """
        WEBVTT

        00:00:01.200 --> 00:00:03.400
        Hello
        world

        01:01:01.005 --> 01:01:02.500
        Done

        """)
    }

    @Test("plain text serializer emits cue text only")
    func plainTextSerializerEmitsCueTextOnly() throws {
        let track = try sampleTrack()

        let text = PlainTextCaptionSerializer.serialize(track)

        #expect(
            text == """
        Hello
        world

        Done

        """)
    }

    @Test("serializers handle empty tracks")
    func serializersHandleEmptyTracks() throws {
        let track = try CaptionTrack(cues: [], language: Locale.LanguageCode("en"))

        #expect(SRTCaptionSerializer.serialize(track) == "")
        #expect(VTTCaptionSerializer.serialize(track) == "WEBVTT\n")
        #expect(PlainTextCaptionSerializer.serialize(track) == "")
    }

}

extension CaptionModelTests {
    @Test("export time mapper trims and scales cues")
    func exportTimeMapperTrimsAndScalesCues() throws {
        let track = try CaptionTrack(
            cues: [
                cue(start: 0.5, end: 1.5, text: "Before"),
                cue(start: 1.5, end: 2.5, text: "Starts before trim"),
                cue(start: 3, end: 5, text: "Inside"),
                cue(start: 5.5, end: 6.5, text: "Ends after trim"),
                cue(start: 6.5, end: 7, text: "After")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .system
        )
        let mapper = try CaptionExportTimeMapper(
            trimRange: TimeRange(start: 2, end: 6),
            speed: PlaybackSpeed(2)
        )

        let mapped = try mapper.map(track)
        let expectedCues = [
            try cue(start: 0, end: 0.25, text: "Starts before trim"),
            try cue(start: 0.5, end: 1.5, text: "Inside"),
            try cue(start: 1.75, end: 2, text: "Ends after trim")
        ]

        #expect(mapped.language == Locale.LanguageCode("en"))
        #expect(mapped.sourceTrack == .system)
        #expect(mapped.cues == expectedCues)
    }

    @Test("cue builder segments sentences and wraps caption lines")
    func cueBuilderSegmentsSentencesAndWrapsCaptionLines() throws {
        let builder = CaptionCueBuilder(
            configuration: try CaptionCueBuilderConfiguration(
                maxCharactersPerLine: 18,
                minimumDuration: 0.8,
                maximumDuration: 6,
                speechPauseThreshold: 0.6
            ))

        let cues = try builder.buildCues(from: [
            word(start: 0, duration: 0.4, text: "Hello"),
            word(start: 0.45, duration: 0.45, text: "world."),
            word(start: 1.4, duration: 0.3, text: "Another"),
            word(start: 1.75, duration: 0.3, text: "caption"),
            word(start: 2.1, duration: 0.3, text: "wraps"),
            word(start: 2.45, duration: 0.3, text: "nicely")
        ])

        #expect(
            cues.map(\.text) == [
                "Hello world.",
                "Another caption\nwraps nicely"
            ])
        #expect(cues[0].timeRange == (try TimeRange(start: 0, end: 0.9)))
        #expect(cues[1].timeRange == (try TimeRange(start: 1.4, end: 2.75)))
    }

    @Test("cue builder snaps to speech pauses and keeps low confidence words")
    func cueBuilderSnapsToSpeechPausesAndKeepsLowConfidenceWords() throws {
        let builder = CaptionCueBuilder(
            configuration: try CaptionCueBuilderConfiguration(
                minimumDuration: 0.8,
                maximumDuration: 6,
                speechPauseThreshold: 0.6
            ))

        let cues = try builder.buildCues(from: [
            word(start: 0, duration: 0.4, text: "quiet"),
            word(start: 0.45, duration: 0.4, text: "pause"),
            word(start: 1.8, duration: 0.35, text: "uncertain", confidence: 0.05),
            word(start: 2.2, duration: 0.35, text: "word")
        ])

        #expect(
            cues.map(\.text) == [
                "quiet pause",
                "uncertain word"
            ])
        #expect(cues[0].timeRange.start == 0)
        #expect(abs(cues[0].timeRange.end - 0.85) < 0.000_001)
        #expect(cues[1].timeRange == (try TimeRange(start: 1.8, end: 2.6)))

        let shortPauseCues = try builder.buildCues(from: [
            word(start: 4, duration: 0.1, text: "short"),
            word(start: 5, duration: 0.2, text: "after")
        ])
        #expect(shortPauseCues.map(\.text) == ["short", "after"])
        #expect(shortPauseCues[0].timeRange == (try TimeRange(start: 4, end: 4.8)))
        #expect(shortPauseCues[1].timeRange == (try TimeRange(start: 5, end: 5.8)))
    }

    @Test("cue builder enforces maximum duration and validates recognized words")
    func cueBuilderEnforcesMaximumDurationAndValidatesRecognizedWords() throws {
        let builder = CaptionCueBuilder(
            configuration: try CaptionCueBuilderConfiguration(
                maxCharactersPerLine: 64,
                minimumDuration: 0.8,
                maximumDuration: 2,
                speechPauseThreshold: 1
            ))

        let cues = try builder.buildCues(from: [
            word(start: 0, duration: 0.4, text: "one"),
            word(start: 0.5, duration: 0.4, text: "two"),
            word(start: 1, duration: 0.4, text: "three"),
            word(start: 1.5, duration: 0.4, text: "four"),
            word(start: 2, duration: 0.4, text: "five")
        ])

        #expect(
            cues.map(\.text) == [
                "one two three four",
                "five"
            ])
        #expect(cues[0].timeRange == (try TimeRange(start: 0, end: 1.9)))
        #expect(cues[1].timeRange == (try TimeRange(start: 2, end: 2.8)))

        #expect(throws: CaptionModelError.invalidRecognizedWord) {
            _ = try word(start: 0, duration: 0.1, text: " ")
        }
        #expect(throws: CaptionModelError.invalidConfidence) {
            _ = try word(start: 0, duration: 0.1, text: "word", confidence: 1.1)
        }
        #expect(throws: CaptionModelError.unsortedRecognizedWords) {
            _ = try builder.buildCues(from: [
                word(start: 1, duration: 0.1, text: "later"),
                word(start: 0, duration: 0.1, text: "earlier")
            ])
        }
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

    private func word(
        start: TimeInterval,
        duration: TimeInterval,
        text: String,
        confidence: Double = 1
    ) throws -> RecognizedWord {
        try RecognizedWord(
            start: start,
            duration: duration,
            text: text,
            confidence: confidence
        )
    }
}
