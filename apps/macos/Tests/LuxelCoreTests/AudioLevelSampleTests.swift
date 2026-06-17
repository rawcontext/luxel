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

    @Test("combined adds active source power and clamps peak")
    func combinedAddsActiveSourcePowerAndClampsPeak() {
        let sample = AudioLevelSample.combined([
            AudioLevelSample(rms: 0.3, peak: 0.7),
            AudioLevelSample(rms: 0.4, peak: 0.5)
        ])

        #expect(sample.rms > 0.49)
        #expect(sample.rms < 0.51)
        #expect(sample.peak == 1)
    }

    @Test("combined treats no sources as silence")
    func combinedTreatsNoSourcesAsSilence() {
        #expect(AudioLevelSample.combined([]) == .silent)
    }

    @Test("broadcaster publishes recording samples to listeners")
    func broadcasterPublishesRecordingSamplesToListeners() async {
        let broadcaster = AudioLevelBroadcaster()
        var iterator = broadcaster.start(deviceID: nil).makeAsyncIterator()

        #expect(await iterator.next() == .silent)

        let sample = AudioLevelSample(rms: 0.25, peak: 0.75)
        broadcaster.publish(sample)

        #expect(await iterator.next() == sample)

        broadcaster.stop()
        #expect(await iterator.next() == nil)
    }
}
