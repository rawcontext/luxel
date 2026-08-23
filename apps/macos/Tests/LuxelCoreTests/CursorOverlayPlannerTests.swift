import Foundation
import LuxelCore
import Testing

@Suite("Cursor overlay planner")
struct CursorOverlayPlannerTests {
    @Test("planner resolves cursor placement from smoothed samples and hotspot")
    func plannerResolvesCursorPlacementFromSmoothedSamplesAndHotspot() throws {
        let image = try cursorImage(hotspot: CursorPoint(x: 2, y: 3))
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 0, y: 0),
                try cursorSample(time: 1, x: 10, y: 10)
            ],
            cursorImages: [image]
        )
        let options = try CursorRenderOptions(sizeMultiplier: 2)

        let plan = try CursorOverlayPlanner.plan(
            at: 0.5,
            timeline: timeline,
            options: options,
            frameSize: PixelSize(width: 100, height: 100),
            recordingDuration: 1
        )
        let cursor = try #require(plan.cursor)

        #expect(plan.time == 0.5)
        #expect(cursor.image == image)
        #expect(cursor.hotspotPosition == (try CursorPoint(x: 5, y: 5)))
        #expect(cursor.imageOrigin == (try CursorPoint(x: 1, y: -1)))
        #expect(cursor.sizeMultiplier == 2)
        #expect(plan.clickEffects.isEmpty)
        #expect(plan.spotlight == nil)
    }

    @Test("planner emits active click effects anchored to click-time cursor position")
    func plannerEmitsActiveClickEffectsAnchoredToClickTimeCursorPosition() throws {
        let color = try CursorRGBAColor(red: 1, green: 0, blue: 0, alpha: 0.75)
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 0, y: 0),
                try cursorSample(time: 1, x: 10, y: 10)
            ],
            clicks: [
                try CursorClickEvent(time: 0.2, button: .left, phase: .down),
                try CursorClickEvent(time: 0.3, button: .left, phase: .released),
                try CursorClickEvent(time: 0.4, button: .right, phase: .released)
            ],
            cursorImages: [try cursorImage()]
        )
        let options = try CursorRenderOptions(
            clickStyle: .ringRipple,
            clickColor: color,
            clickSize: 1.5,
            clickDuration: 0.5
        )

        let activePlan = try CursorOverlayPlanner.plan(
            at: 0.45,
            timeline: timeline,
            options: options,
            frameSize: PixelSize(width: 100, height: 100),
            recordingDuration: 1
        )
        let effect = try #require(activePlan.clickEffects.first)
        let expiredPlan = try CursorOverlayPlanner.plan(
            at: 0.75,
            timeline: timeline,
            options: options,
            frameSize: PixelSize(width: 100, height: 100),
            recordingDuration: 1
        )

        #expect(activePlan.clickEffects.count == 1)
        #expect(effect.event.button == .left)
        #expect(effect.timeRange == (try TimeRange(start: 0.2, end: 0.7)))
        #expect(effect.center == (try CursorPoint(x: 2, y: 2)))
        #expect(effect.style == .ringRipple)
        #expect(effect.color == color)
        #expect(effect.sizeMultiplier == 1.5)
        #expect(abs(effect.progress - 0.5) < 0.000_001)
        #expect(expiredPlan.clickEffects.isEmpty)
    }

    @Test("planner resolves spotlight from toggles or whole-recording mode")
    func plannerResolvesSpotlightFromTogglesOrWholeRecordingMode() throws {
        let spotlight = try CursorSpotlightOptions(radius: 120, dimOpacity: 0.4)
        let options = try CursorRenderOptions(spotlight: spotlight)
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 0, y: 0),
                try cursorSample(time: 1, x: 10, y: 10)
            ],
            spotlightToggles: [0.25, 0.75],
            cursorImages: [try cursorImage()]
        )
        let frameSize = try PixelSize(width: 100, height: 100)

        let beforeToggle = try CursorOverlayPlanner.plan(
            at: 0.2,
            timeline: timeline,
            options: options,
            frameSize: frameSize,
            recordingDuration: 1
        )
        let insideToggle = try CursorOverlayPlanner.plan(
            at: 0.5,
            timeline: timeline,
            options: options,
            frameSize: frameSize,
            recordingDuration: 1
        )
        let afterToggle = try CursorOverlayPlanner.plan(
            at: 0.75,
            timeline: timeline,
            options: options,
            frameSize: frameSize,
            recordingDuration: 1
        )
        let wholeRecordingTimeline = try CursorTimeline(
            samples: timeline.samples,
            cursorImages: timeline.cursorImages
        )
        let wholeRecording = try CursorOverlayPlanner.plan(
            at: 0.5,
            timeline: wholeRecordingTimeline,
            options: options,
            frameSize: frameSize,
            recordingDuration: 1
        )

        #expect(beforeToggle.spotlight == nil)
        #expect(insideToggle.spotlight?.center == (try CursorPoint(x: 5, y: 5)))
        #expect(insideToggle.spotlight?.options == spotlight)
        #expect(afterToggle.spotlight == nil)
        #expect(wholeRecording.spotlight?.center == (try CursorPoint(x: 5, y: 5)))
    }

    @Test("planner treats out of bounds samples as render gaps")
    func plannerTreatsOutOfBoundsSamplesAsRenderGaps() throws {
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 0, y: 0),
                try cursorSample(time: 1, x: -10, y: 10),
                try cursorSample(time: 2, x: 20, y: 20)
            ],
            clicks: [
                try CursorClickEvent(time: 1, button: .left, phase: .down)
            ],
            cursorImages: [try cursorImage()]
        )
        let options = try CursorRenderOptions(
            clickStyle: .filledPulse,
            clickDuration: 1,
            spotlight: CursorSpotlightOptions(radius: 80, dimOpacity: 0.5)
        )

        let plan = try CursorOverlayPlanner.plan(
            at: 1,
            timeline: timeline,
            options: options,
            frameSize: PixelSize(width: 100, height: 100),
            recordingDuration: 2
        )

        #expect(plan.isEmpty)
    }

    @Test("planner validates frame time and recording duration")
    func plannerValidatesFrameTimeAndRecordingDuration() throws {
        let timeline = try CursorTimeline(cursorImages: [try cursorImage()])

        #expect(throws: CursorEffectModelError.invalidRecordingDuration) {
            _ = try CursorOverlayPlanner.plan(
                at: 0,
                timeline: timeline,
                options: .standard,
                frameSize: PixelSize(width: 100, height: 100),
                recordingDuration: .infinity
            )
        }
        #expect(throws: CursorEffectModelError.invalidTime) {
            _ = try CursorOverlayPlanner.plan(
                at: 2,
                timeline: timeline,
                options: .standard,
                frameSize: PixelSize(width: 100, height: 100),
                recordingDuration: 1
            )
        }
    }

    @Test("planner rejects duplicate image ids from decoded sidecars")
    func plannerRejectsDuplicateImageIDsFromDecodedSidecars() throws {
        let timeline = try JSONDecoder().decode(
            CursorTimeline.self,
            from: Data(
                """
                {
                  "schemaVersion": 1,
                  "samples": [
                    {
                      "time": 0,
                      "position": { "x": 0, "y": 0 },
                      "cursorImageID": "arrow"
                    }
                  ],
                  "clicks": [],
                  "spotlightToggles": [],
                  "cursorImages": [
                    {
                      "id": "arrow",
                      "pngData": "AQ==",
                      "hotspot": { "x": 1, "y": 1 },
                      "scale": 2
                    },
                    {
                      "id": "arrow",
                      "pngData": "Ag==",
                      "hotspot": { "x": 1, "y": 1 },
                      "scale": 2
                    }
                  ]
                }
                """.utf8)
        )

        #expect(throws: CursorEffectModelError.duplicateCursorImageID) {
            _ = try CursorOverlayPlanner.plan(
                at: 0,
                timeline: timeline,
                options: .standard,
                frameSize: PixelSize(width: 100, height: 100),
                recordingDuration: 1
            )
        }
    }

    private func cursorImage(
        id: String = "arrow",
        hotspot: CursorPoint? = nil
    ) throws -> CursorImageAsset {
        try testCursorImage(id: id, hotspot: hotspot ?? CursorPoint(x: 1, y: 1))
    }

    private func cursorSample(time: TimeInterval, x xCoordinate: Double, y yCoordinate: Double) throws
        -> CursorSample
    {
        try testCursorSample(time: time, x: xCoordinate, y: yCoordinate)
    }
}
