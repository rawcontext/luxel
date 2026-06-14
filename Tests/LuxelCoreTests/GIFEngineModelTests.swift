import Foundation
import LuxelCore
import Testing

@Suite("GIF engine models")
struct GIFEngineModelTests {
    @Test("loop modes validate codable storage and ImageIO loop counts")
    func loopModesValidateCodableStorageAndImageIOLoopCounts() throws {
        let counted = try GIFLoopMode.counted(3)

        #expect(GIFLoopMode.forever.imageIOLoopCount == 0)
        #expect(GIFLoopMode.bounce.imageIOLoopCount == 0)
        #expect(GIFLoopMode.none.imageIOLoopCount == nil)
        #expect(counted.imageIOLoopCount == 3)
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try GIFLoopMode.counted(0)
        }
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try GIFLoopMode.counted(101)
        }

        let data = try JSONEncoder().encode(counted)
        let decoded = try JSONDecoder().decode(GIFLoopMode.self, from: data)
        #expect(decoded == counted)

        let invalidData = #"{"kind":"count","count":0}"#.data(using: .utf8) ?? Data()
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try JSONDecoder().decode(GIFLoopMode.self, from: invalidData)
        }
    }

    @Test("render options validate defaults quality mapping and codable storage")
    func renderOptionsValidateDefaultsQualityMappingAndCodableStorage() throws {
        let standard = GIFRenderOptions.standard
        let compact = try GIFRenderOptions(quality: .compact)
        let balanced = try GIFRenderOptions(quality: .balanced)
        let matte = try RGBColor(red: 0.1, green: 0.2, blue: 0.3)
        let custom = try GIFRenderOptions(
            loopMode: .bounce,
            dithering: .ordered,
            paletteSize: 16,
            lossyTolerance: 4,
            backgroundMatte: matte
        )

        #expect(standard.loopMode == .forever)
        #expect(standard.dithering == .auto)
        #expect(standard.paletteSize == 256)
        #expect(standard.lossyTolerance == 0)
        #expect(standard.backgroundMatte == nil)
        #expect(compact.paletteSize == 128)
        #expect(compact.lossyTolerance == 8)
        #expect(balanced.paletteSize == 256)
        #expect(balanced.lossyTolerance == 0)
        #expect(custom.backgroundMatte == matte)

        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(GIFRenderOptions.self, from: data)
        #expect(decoded == custom)

        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try GIFRenderOptions(paletteSize: 1)
        }
        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try GIFRenderOptions(paletteSize: 257)
        }
        #expect(throws: GIFEngineModelError.invalidLossyTolerance) {
            _ = try GIFRenderOptions(lossyTolerance: 33)
        }
        #expect(throws: GIFEngineModelError.unsupportedQuality(.lossless)) {
            _ = try GIFRenderOptions(quality: .lossless)
        }
        #expect(throws: GIFEngineModelError.invalidColor) {
            _ = try RGBColor(red: 1.1, green: 0, blue: 0)
        }
    }

    @Test("delay planner diffuses centisecond drift")
    func delayPlannerDiffusesCentisecondDrift() throws {
        let frameDuration = 1.0 / 24.0
        let plan = try CentisecondDelayPlanner().plan(
            frameCount: 1_000,
            frameDuration: frameDuration
        )
        let expectedDuration = frameDuration * 1_000

        #expect(Set(plan.centisecondDelays) == [4, 5])
        #expect(abs(plan.totalDuration - expectedDuration) < 0.01)
        #expect(plan.delays.allSatisfy { $0 == 0.04 || $0 == 0.05 })
    }

    @Test("delay planner validates frame counts and durations")
    func delayPlannerValidatesFrameCountsAndDurations() throws {
        let planner = CentisecondDelayPlanner()

        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try planner.plan(frameCount: 0, frameDuration: 0.1)
        }
        #expect(throws: GIFEngineModelError.invalidFrameDuration) {
            _ = try planner.plan(frameCount: 1, frameDuration: 0)
        }
        #expect(throws: GIFEngineModelError.invalidFrameDuration) {
            _ = try planner.plan(frameDurations: [0.1, .infinity])
        }
        #expect(throws: GIFEngineModelError.invalidCentisecondDelay) {
            _ = try GIFCentisecondDelayPlan(centisecondDelays: [2, 0])
        }
    }

    @Test("frame sequence planner bounces without duplicating the last frame")
    func frameSequencePlannerBouncesWithoutDuplicatingTheLastFrame() throws {
        let planner = GIFFrameSequencePlanner()

        #expect(try planner.frameIndexes(frameCount: 4, loopMode: .forever) == [0, 1, 2, 3])
        #expect(try planner.frameIndexes(frameCount: 4, loopMode: .none) == [0, 1, 2, 3])
        #expect(try planner.frameIndexes(frameCount: 1, loopMode: .bounce) == [0])

        let bounced = try planner.frameIndexes(frameCount: 4, loopMode: .bounce)
        #expect(bounced == [0, 1, 2, 3, 2, 1, 0])
        #expect(bounced.filter { $0 == 3 }.count == 1)

        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try planner.frameIndexes(frameCount: 0, loopMode: .forever)
        }
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try planner.frameIndexes(frameCount: 4, loopMode: .count(0))
        }
    }
}
