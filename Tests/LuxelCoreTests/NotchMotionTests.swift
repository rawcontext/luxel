import LuxelCore
import Testing

@Suite("Notch motion")
struct NotchMotionTests {
    @Test("standard motion uses critically damped morphs and success overshoot")
    func standardMotionUsesExpectedSpringPolicy() {
        let motion = NotchMotion.standard

        #expect(!motion.reducesMotion)
        #expect(motion.morphSpring.dampingRatio == 1)
        #expect(!motion.morphSpring.allowsOvershoot)
        #expect(motion.successSpring.allowsOvershoot)
        #expect(motion.geometryMorphDuration > 0)
        #expect(motion.recordingPulseFrequency == 1)
        #expect(motion.waveformFrameRate == 30)
    }

    @Test("reduced motion removes geometry morph pulse and waveform animation")
    func reducedMotionRemovesMovingEffects() {
        let motion = NotchMotion.reduced

        #expect(motion.reducesMotion)
        #expect(motion.geometryMorphDuration == 0)
        #expect(motion.contentFadeDuration > 0)
        #expect(motion.hoverGraceDuration == 0)
        #expect(motion.completionDwellDuration == NotchMotion.standard.completionDwellDuration)
        #expect(motion.recordingPulseFrequency == 0)
        #expect(motion.waveformFrameRate == 0)
        #expect(!motion.successSpring.allowsOvershoot)
    }

    @Test("motion chooses reduced variant on request")
    func motionChoosesReducedVariantOnRequest() {
        #expect(NotchMotion.standard.variant(reduceMotion: false) == .standard)
        #expect(NotchMotion.standard.variant(reduceMotion: true) == .reduced)
    }

    @Test("spring timing rejects non positive or non finite values")
    func springTimingRejectsInvalidValues() {
        #expect(throws: NotchMotionError.invalidSpring) {
            _ = try NotchSpringTiming(response: 0, dampingRatio: 1)
        }
        #expect(throws: NotchMotionError.invalidSpring) {
            _ = try NotchSpringTiming(response: 0.3, dampingRatio: .nan)
        }
    }

    @Test("motion rejects invalid timing values")
    func motionRejectsInvalidTimingValues() throws {
        let spring = try NotchSpringTiming(response: 0.3, dampingRatio: 1)

        #expect(throws: NotchMotionError.invalidTiming) {
            _ = try NotchMotion(
                reducesMotion: false,
                morphSpring: spring,
                successSpring: spring,
                geometryMorphDuration: -0.1,
                contentFadeDuration: 0.1,
                hoverGraceDuration: 0,
                completionDwellDuration: 6,
                recordingPulseFrequency: 1,
                waveformFrameRate: 30
            )
        }
        #expect(throws: NotchMotionError.invalidTiming) {
            _ = try NotchMotion(
                reducesMotion: false,
                morphSpring: spring,
                successSpring: spring,
                geometryMorphDuration: 0.2,
                contentFadeDuration: 0.1,
                hoverGraceDuration: 0,
                completionDwellDuration: 6,
                recordingPulseFrequency: .infinity,
                waveformFrameRate: 30
            )
        }
    }
}
