import LuxelCore
import Testing

@Suite("Audio level sample")
struct AudioLevelSampleTests {
    @Test("init clamps invalid and out of range levels")
    func initClampsInvalidAndOutOfRangeLevels() {
        #expect(AudioLevelSample(rms: -1, peak: 2) == AudioLevelSample(rms: 0, peak: 1))
        #expect(AudioLevelSample(rms: .nan, peak: .infinity) == .silent)
    }

    @Test("fromDecibels converts average and peak power to normalized levels")
    func fromDecibelsConvertsPowerLevels() {
        let sample = AudioLevelSample.fromDecibels(
            averageLevels: [-6, -12],
            peakLevels: [-3, -9]
        )

        #expect(sample.rms > 0.35)
        #expect(sample.rms < 0.4)
        #expect(sample.peak > 0.7)
        #expect(sample.peak < 0.71)
    }

    @Test("fromDecibels treats very low or invalid levels as silence")
    func fromDecibelsTreatsLowOrInvalidLevelsAsSilence() {
        let sample = AudioLevelSample.fromDecibels(
            averageLevels: [-160, .nan],
            peakLevels: [-160, .infinity]
        )

        #expect(sample.rms < 0.0001)
        #expect(sample.peak <= 0.0001)
    }
}
