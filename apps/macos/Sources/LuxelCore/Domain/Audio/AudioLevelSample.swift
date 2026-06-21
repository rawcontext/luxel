import Foundation

public struct AudioLevelSample: Equatable, Sendable {
    public static let silent = AudioLevelSample(rms: 0, peak: 0)

    public let rms: Double
    public let peak: Double

    public init(rms: Double, peak: Double) {
        self.rms = Self.clamp(rms)
        self.peak = Self.clamp(peak)
    }

    public static func fromDecibels(averageLevels: [Float], peakLevels: [Float]) -> AudioLevelSample {
        AudioLevelSample(
            rms: averageLevels.map(linearPower).average(),
            peak: peakLevels.map(linearPower).max() ?? 0
        )
    }

    public static func combined(_ samples: [AudioLevelSample]) -> AudioLevelSample {
        guard !samples.isEmpty else {
            return .silent
        }

        let rms = sqrt(
            samples.reduce(0) { total, sample in
                total + (sample.rms * sample.rms)
            })
        let peak = samples.reduce(0) { total, sample in
            total + sample.peak
        }

        return AudioLevelSample(rms: rms, peak: peak)
    }

    private static func linearPower(decibels: Float) -> Double {
        guard decibels.isFinite else {
            return 0
        }

        let clampedDecibels = min(0, max(-80, Double(decibels)))
        return pow(10, clampedDecibels / 20)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return min(1, max(0, value))
    }
}

extension [Double] {
    fileprivate func average() -> Double {
        guard !isEmpty else {
            return 0
        }

        return reduce(0, +) / Double(count)
    }
}
