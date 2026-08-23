import Foundation

public struct NotchMotion: Codable, Equatable, Sendable {
    public static let standard = NotchMotion(
        uncheckedReducesMotion: false,
        morphSpring: NotchSpringTiming(uncheckedResponse: 0.34, dampingRatio: 1),
        successSpring: NotchSpringTiming(uncheckedResponse: 0.42, dampingRatio: 0.78),
        geometryMorphDuration: 0.34,
        contentFadeDuration: 0.14,
        hoverGraceDuration: 0.22,
        completionDwellDuration: 6,
        recordingPulseFrequency: 1,
        waveformFrameRate: 30
    )

    public static let reduced = NotchMotion(
        uncheckedReducesMotion: true,
        morphSpring: NotchSpringTiming(uncheckedResponse: 0.01, dampingRatio: 1),
        successSpring: NotchSpringTiming(uncheckedResponse: 0.01, dampingRatio: 1),
        geometryMorphDuration: 0,
        contentFadeDuration: 0.12,
        hoverGraceDuration: 0,
        completionDwellDuration: 6,
        recordingPulseFrequency: 0,
        waveformFrameRate: 0
    )

    public let reducesMotion: Bool
    public let morphSpring: NotchSpringTiming
    public let successSpring: NotchSpringTiming
    public let geometryMorphDuration: TimeInterval
    public let contentFadeDuration: TimeInterval
    public let hoverGraceDuration: TimeInterval
    public let completionDwellDuration: TimeInterval
    public let recordingPulseFrequency: Double
    public let waveformFrameRate: Double

    private init(
        uncheckedReducesMotion reducesMotion: Bool,
        morphSpring: NotchSpringTiming,
        successSpring: NotchSpringTiming,
        geometryMorphDuration: TimeInterval,
        contentFadeDuration: TimeInterval,
        hoverGraceDuration: TimeInterval,
        completionDwellDuration: TimeInterval,
        recordingPulseFrequency: Double,
        waveformFrameRate: Double
    ) {
        self.reducesMotion = reducesMotion
        self.morphSpring = morphSpring
        self.successSpring = successSpring
        self.geometryMorphDuration = geometryMorphDuration
        self.contentFadeDuration = contentFadeDuration
        self.hoverGraceDuration = hoverGraceDuration
        self.completionDwellDuration = completionDwellDuration
        self.recordingPulseFrequency = recordingPulseFrequency
        self.waveformFrameRate = waveformFrameRate
    }

    public init(
        reducesMotion: Bool,
        morphSpring: NotchSpringTiming,
        successSpring: NotchSpringTiming,
        geometryMorphDuration: TimeInterval,
        contentFadeDuration: TimeInterval,
        hoverGraceDuration: TimeInterval,
        completionDwellDuration: TimeInterval,
        recordingPulseFrequency: Double,
        waveformFrameRate: Double
    ) throws {
        guard geometryMorphDuration.isFinite, geometryMorphDuration >= 0,
            contentFadeDuration.isFinite, contentFadeDuration >= 0,
            hoverGraceDuration.isFinite, hoverGraceDuration >= 0,
            completionDwellDuration.isFinite, completionDwellDuration >= 0,
            recordingPulseFrequency.isFinite, recordingPulseFrequency >= 0,
            waveformFrameRate.isFinite, waveformFrameRate >= 0
        else {
            throw NotchMotionError.invalidTiming
        }

        self.reducesMotion = reducesMotion
        self.morphSpring = morphSpring
        self.successSpring = successSpring
        self.geometryMorphDuration = geometryMorphDuration
        self.contentFadeDuration = contentFadeDuration
        self.hoverGraceDuration = hoverGraceDuration
        self.completionDwellDuration = completionDwellDuration
        self.recordingPulseFrequency = recordingPulseFrequency
        self.waveformFrameRate = waveformFrameRate
    }

    public func variant(reduceMotion: Bool) -> NotchMotion {
        reduceMotion ? .reduced : self
    }
}

public struct NotchSpringTiming: Codable, Equatable, Sendable {
    public let response: TimeInterval
    public let dampingRatio: Double

    public init(response: TimeInterval, dampingRatio: Double) throws {
        guard response.isFinite, response > 0, dampingRatio.isFinite, dampingRatio > 0 else {
            throw NotchMotionError.invalidSpring
        }

        self.response = response
        self.dampingRatio = dampingRatio
    }

    fileprivate init(uncheckedResponse response: TimeInterval, dampingRatio: Double) {
        self.response = response
        self.dampingRatio = dampingRatio
    }

    public var allowsOvershoot: Bool {
        dampingRatio < 1
    }
}

public enum NotchMotionError: Error, Equatable {
    case invalidSpring
    case invalidTiming
}
