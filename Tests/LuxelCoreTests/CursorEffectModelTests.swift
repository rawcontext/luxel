import Foundation
import LuxelCore
import Testing

@Suite("Cursor effect models")
struct CursorEffectModelTests {
    @Test("timeline stores sorted samples clicks toggles and cursor images")
    func timelineStoresSortedEventsAndImages() throws {
        let arrow = try cursorImage(id: "arrow")
        let timeline = try CursorTimeline(
            samples: [
                try CursorSample(time: 0, position: CursorPoint(x: 10, y: 20), cursorImageID: "arrow"),
                try CursorSample(time: 0.5, position: CursorPoint(x: 12, y: 24), cursorImageID: "arrow")
            ],
            clicks: [
                try CursorClickEvent(time: 0.25, button: .left, phase: .down),
                try CursorClickEvent(time: 0.35, button: .left, phase: .up)
            ],
            spotlightToggles: [1, 3],
            cursorImages: [arrow]
        )

        #expect(timeline.schemaVersion == CursorTimeline.currentSchemaVersion)
        #expect(timeline.samples.count == 2)
        #expect(timeline.clicks.map(\.phase) == [.down, .up])
        #expect(timeline.spotlightToggles == [1, 3])
        #expect(timeline.cursorImages == [arrow])
    }

    @Test("timeline rejects invalid image references and unsorted events")
    func timelineRejectsInvalidImageReferencesAndUnsortedEvents() throws {
        let arrow = try cursorImage(id: "arrow")
        let duplicateArrow = try cursorImage(id: "arrow")
        let firstSample = try CursorSample(time: 1, position: CursorPoint(x: 0, y: 0), cursorImageID: "arrow")
        let secondSample = try CursorSample(time: 0.5, position: CursorPoint(x: 1, y: 1), cursorImageID: "arrow")
        let missingImageSample = try CursorSample(time: 1, position: CursorPoint(x: 0, y: 0), cursorImageID: "ibeam")

        #expect(throws: CursorEffectModelError.duplicateCursorImageID) {
            _ = try CursorTimeline(samples: [firstSample], cursorImages: [arrow, duplicateArrow])
        }
        #expect(throws: CursorEffectModelError.unsortedEvents) {
            _ = try CursorTimeline(samples: [firstSample, secondSample], cursorImages: [arrow])
        }
        #expect(throws: CursorEffectModelError.missingCursorImage) {
            _ = try CursorTimeline(samples: [missingImageSample], cursorImages: [arrow])
        }
        #expect(throws: CursorEffectModelError.unsortedEvents) {
            _ = try CursorTimeline(spotlightToggles: [2, 1], cursorImages: [arrow])
        }
        #expect(throws: CursorEffectModelError.unsupportedSchemaVersion) {
            _ = try CursorTimeline(schemaVersion: 2)
        }
    }

    @Test("render options validate cursor click and spotlight values")
    func renderOptionsValidateValues() throws {
        let spotlight = try CursorSpotlightOptions(
            radius: 180,
            dimOpacity: 0.5,
            dimColor: CursorRGBAColor(red: 0, green: 0, blue: 0, alpha: 0.9),
            feather: 0.2
        )
        let options = try CursorRenderOptions(
            isVisible: true,
            sizeMultiplier: 2,
            smoothing: .light,
            clickStyle: .ringRipple,
            clickColor: CursorRGBAColor(red: 1, green: 0, blue: 0),
            clickSize: 1.5,
            clickDuration: 0.7,
            spotlight: spotlight
        )

        #expect(options.sizeMultiplier == 2)
        #expect(options.smoothing == .light)
        #expect(options.clickStyle == .ringRipple)
        #expect(options.spotlight == spotlight)

        #expect(throws: CursorEffectModelError.invalidRenderOption) {
            _ = try CursorRenderOptions(sizeMultiplier: 0.9)
        }
        #expect(throws: CursorEffectModelError.invalidRenderOption) {
            _ = try CursorRenderOptions(clickSize: 0)
        }
        #expect(throws: CursorEffectModelError.invalidRenderOption) {
            _ = try CursorRenderOptions(clickDuration: .infinity)
        }
        #expect(throws: CursorEffectModelError.invalidColor) {
            _ = try CursorRGBAColor(red: 1.1, green: 0, blue: 0)
        }
        #expect(throws: CursorEffectModelError.invalidRenderOption) {
            _ = try CursorSpotlightOptions(radius: 0, dimOpacity: 0.5)
        }
        #expect(throws: CursorEffectModelError.invalidRenderOption) {
            _ = try CursorSpotlightOptions(radius: 100, dimOpacity: 1.1)
        }
    }

    @Test("media time mapper drops pause intervals and shifts resumed events")
    func mediaTimeMapperDropsPauseIntervalsAndShiftsResumedEvents() throws {
        let mapper = try MediaTimeMapper(
            recordingDuration: 20,
            pauses: [
                MediaPauseInterval(start: 5, end: 8),
                MediaPauseInterval(start: 12, end: 15)
            ]
        )

        #expect(mapper.mediaDuration == 14)
        #expect(mapper.mediaTime(forWallTime: 4) == 4)
        #expect(mapper.mediaTime(forWallTime: 5) == nil)
        #expect(mapper.mediaTime(forWallTime: 7) == nil)
        #expect(mapper.mediaTime(forWallTime: 8) == 5)
        #expect(mapper.mediaTime(forWallTime: 13) == nil)
        #expect(mapper.mediaTime(forWallTime: 16) == 10)
        #expect(mapper.mediaTime(forWallTime: 21) == nil)
    }

    @Test("media time mapper validates pause intervals")
    func mediaTimeMapperValidatesPauseIntervals() throws {
        #expect(throws: CursorEffectModelError.invalidRecordingDuration) {
            _ = try MediaTimeMapper(recordingDuration: .infinity)
        }
        #expect(throws: CursorEffectModelError.invalidPauseInterval) {
            _ = try MediaPauseInterval(start: 2, end: 2)
        }
        #expect(throws: CursorEffectModelError.invalidPauseInterval) {
            _ = try MediaTimeMapper(
                recordingDuration: 5,
                pauses: [MediaPauseInterval(start: 2, end: 6)]
            )
        }
        #expect(throws: CursorEffectModelError.overlappingPauseIntervals) {
            _ = try MediaTimeMapper(
                recordingDuration: 10,
                pauses: [
                    MediaPauseInterval(start: 2, end: 5),
                    MediaPauseInterval(start: 4, end: 6)
                ]
            )
        }
        #expect(throws: CursorEffectModelError.unsortedEvents) {
            _ = try MediaTimeMapper(
                recordingDuration: 10,
                pauses: [
                    MediaPauseInterval(start: 5, end: 6),
                    MediaPauseInterval(start: 2, end: 3)
                ]
            )
        }
    }

    @Test("spotlight resolver pairs toggles and closes unclosed interval")
    func spotlightResolverPairsTogglesAndClosesUnclosedInterval() throws {
        let intervals = try SpotlightIntervalResolver.intervals(
            from: [2, 5, 8],
            recordingDuration: 10
        )

        #expect(intervals.map(\.timeRange.start) == [2, 8])
        #expect(intervals.map(\.timeRange.end) == [5, 10])

        #expect(throws: CursorEffectModelError.invalidTime) {
            _ = try SpotlightIntervalResolver.intervals(from: [2, 11], recordingDuration: 10)
        }
        #expect(throws: CursorEffectModelError.unsortedEvents) {
            _ = try SpotlightIntervalResolver.intervals(from: [3, 2], recordingDuration: 10)
        }
        #expect(throws: CursorEffectModelError.invalidRecordingDuration) {
            _ = try SpotlightIntervalResolver.intervals(from: [], recordingDuration: .infinity)
        }
    }

    private func cursorImage(id: String) throws -> CursorImageAsset {
        try CursorImageAsset(
            id: id,
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            hotspot: CursorPoint(x: 1, y: 2),
            scale: 2
        )
    }
}
