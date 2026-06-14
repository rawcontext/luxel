import Foundation
import LuxelCore
import Testing

@Suite("Audio mix plan")
struct AudioMixPlanTests {
    @Test("track mix clamps volume to supported range")
    func trackMixClampsVolumeToSupportedRange() {
        let quiet = AudioTrackMix(kind: .system, volume: -0.25)
        let loud = AudioTrackMix(kind: .microphone, volume: 2.5)

        #expect(quiet.volume == 0)
        #expect(quiet.gain == 0)
        #expect(loud.volume == 2)
        #expect(loud.gain == 2)
    }

    @Test("plan reports muted only when every track resolves to zero gain")
    func planReportsMutedOnlyWhenEveryTrackResolvesToZeroGain() {
        let active = AudioMixPlan(tracks: [
            AudioTrackMix(kind: .system, volume: 0),
            AudioTrackMix(kind: .microphone, volume: 0.6)
        ])
        let muted = AudioMixPlan(tracks: [
            AudioTrackMix(kind: .system, isMuted: true),
            AudioTrackMix(kind: .microphone, volume: 0)
        ])

        #expect(!active.isMuted)
        #expect(muted.isMuted)
    }

    @Test("duplicate track entries keep first value")
    func duplicateTrackEntriesKeepFirstValue() {
        let plan = AudioMixPlan(tracks: [
            AudioTrackMix(kind: .system, volume: 0.4),
            AudioTrackMix(kind: .system, volume: 1.8)
        ])

        #expect(plan.tracks == [AudioTrackMix(kind: .system, volume: 0.4)])
        #expect(plan.mix(for: .system).volume == 0.4)
        #expect(plan.mix(for: .microphone).isMuted)
    }

    @Test("resolved gains use track gain when normalization is disabled")
    func resolvedGainsUseTrackGainWhenNormalizationIsDisabled() {
        let plan = AudioMixPlan(tracks: [
            AudioTrackMix(kind: .system, volume: 0.5),
            AudioTrackMix(kind: .microphone, volume: 1.5, isMuted: true)
        ])

        #expect(plan.resolvedGains() == [
            .system: 0.5,
            .microphone: 0
        ])
    }

    @Test("peak normalization targets minus one dBFS")
    func peakNormalizationTargetsMinusOneDBFS() {
        let plan = AudioMixPlan(
            tracks: [
                AudioTrackMix(kind: .system, volume: 1),
                AudioTrackMix(kind: .microphone, volume: 0.5)
            ],
            normalizePeak: true
        )

        let gains = plan.resolvedGains(measuredPeaks: [
            .system: 0.5,
            .microphone: 0.8
        ])

        #expect(isApproximately(gains[.system], AudioMixPlan.normalizationTargetPeak / 0.5))
        #expect(isApproximately(gains[.microphone], AudioMixPlan.normalizationTargetPeak))
    }

    @Test("normalization leaves gains unchanged without measured peaks")
    func normalizationLeavesGainsUnchangedWithoutMeasuredPeaks() {
        let plan = AudioMixPlan(
            tracks: [AudioTrackMix(kind: .system, volume: 1.2)],
            normalizePeak: true
        )

        #expect(plan.resolvedGains() == [.system: 1.2])
    }

    private func isApproximately(
        _ lhs: Double?,
        _ rhs: Double,
        tolerance: Double = 0.000_001
    ) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs - rhs) <= tolerance
    }
}
