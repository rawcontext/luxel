import Foundation
import LuxelCore
import Testing

@Suite("Cursor effect models")
struct CursorEffectModelTests {
    @Test("coordinate mapper converts global points to capture-local points")
    func coordinateMapperConvertsGlobalPointsToCaptureLocalPoints() throws {
        let frame = try CaptureRect(x: 1728, y: 90, width: 800, height: 600)

        let point = try CursorCoordinateMapper.localPoint(
            fromGlobalPoint: CursorPoint(x: 1828.5, y: 190.25),
            in: frame
        )

        #expect(point == (try CursorPoint(x: 100.5, y: 100.25)))
    }

    @Test("coordinate mapper preserves points outside capture frame")
    func coordinateMapperPreservesPointsOutsideCaptureFrame() throws {
        let frame = try CaptureRect(x: 500, y: 400, width: 300, height: 200)

        let point = try CursorCoordinateMapper.localPoint(
            fromGlobalPoint: CursorPoint(x: 450, y: 650),
            in: frame
        )

        #expect(point == (try CursorPoint(x: -50, y: 250)))
    }

    @Test("path smoother returns exact samples and linearly interpolates when off")
    func pathSmootherReturnsExactSamplesAndLinearlyInterpolatesWhenOff() throws {
        let samples = [
            try cursorSample(time: 0, x: 0, y: 0),
            try cursorSample(time: 1, x: 10, y: 10)
        ]

        let exact = try CursorPathSmoother.sample(at: 0, from: samples, level: .off)
        let midpoint = try CursorPathSmoother.sample(at: 0.5, from: samples, level: .off)

        #expect(exact == samples[0])
        #expect(midpoint == (try cursorSample(time: 0.5, x: 5, y: 5)))
    }

    @Test("path smoother applies Catmull Rom strength by smoothing level")
    func pathSmootherAppliesCatmullRomStrengthBySmoothingLevel() throws {
        let samples = [
            try cursorSample(time: 0, x: 0, y: 10),
            try cursorSample(time: 1, x: 0, y: 0),
            try cursorSample(time: 2, x: 10, y: 10),
            try cursorSample(time: 3, x: 10, y: -10)
        ]

        let light = try #require(try CursorPathSmoother.sample(at: 1.5, from: samples, level: .light))
        let medium = try #require(try CursorPathSmoother.sample(at: 1.5, from: samples, level: .medium))

        #expect(light.position == (try CursorPoint(x: 5, y: 5.3125)))
        #expect(medium.position == (try CursorPoint(x: 5, y: 5.625)))
        #expect(light.cursorImageID == "arrow")
        #expect(medium.cursorImageID == "arrow")
    }

    @Test("path smoother clamps Catmull Rom overshoot at segment bounds")
    func pathSmootherClampsCatmullRomOvershootAtSegmentBounds() throws {
        let samples = [
            try cursorSample(time: 0, x: 0, y: 0),
            try cursorSample(time: 1, x: 0, y: 0),
            try cursorSample(time: 2, x: 10, y: 0),
            try cursorSample(time: 3, x: 10, y: 10)
        ]

        let smoothed = try #require(try CursorPathSmoother.sample(at: 1.25, from: samples, level: .medium))

        #expect(smoothed.position == (try CursorPoint(x: 2.03125, y: 0)))
    }

    @Test("path smoother treats out of bounds samples as gaps")
    func pathSmootherTreatsOutOfBoundsSamplesAsGaps() throws {
        let samples = [
            try cursorSample(time: 0, x: 0, y: 0),
            try cursorSample(time: 1, x: 10, y: 10),
            try cursorSample(time: 2, x: -10, y: 10),
            try cursorSample(time: 3, x: 20, y: 20)
        ]
        let frameSize = try PixelSize(width: 100, height: 100)

        let visible = try CursorPathSmoother.sample(
            at: 0.5,
            from: samples,
            level: .medium,
            frameSize: frameSize
        )
        let leaving = try CursorPathSmoother.sample(
            at: 1.5,
            from: samples,
            level: .medium,
            frameSize: frameSize
        )
        let outside = try CursorPathSmoother.sample(
            at: 2,
            from: samples,
            level: .medium,
            frameSize: frameSize
        )
        let reentering = try CursorPathSmoother.sample(
            at: 2.5,
            from: samples,
            level: .medium,
            frameSize: frameSize
        )
        let reentered = try CursorPathSmoother.sample(
            at: 3,
            from: samples,
            level: .medium,
            frameSize: frameSize
        )

        #expect(visible != nil)
        #expect(leaving == nil)
        #expect(outside == nil)
        #expect(reentering == nil)
        #expect(reentered == samples[3])
    }

    @Test("path smoother validates sample ordering and target time")
    func pathSmootherValidatesSampleOrderingAndTargetTime() throws {
        let samples = [
            try cursorSample(time: 1, x: 0, y: 0),
            try cursorSample(time: 0, x: 10, y: 10)
        ]

        #expect(throws: CursorEffectModelError.invalidTime) {
            _ = try CursorPathSmoother.sample(at: -.leastNonzeroMagnitude, from: [], level: .off)
        }
        #expect(throws: CursorEffectModelError.unsortedEvents) {
            _ = try CursorPathSmoother.sample(at: 0.5, from: samples, level: .off)
        }
    }

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

    private func cursorSample(time: TimeInterval, x: Double, y: Double) throws -> CursorSample {
        try CursorSample(
            time: time,
            position: CursorPoint(x: x, y: y),
            cursorImageID: "arrow"
        )
    }
}
