import Foundation

public struct CursorRenderOptions: Codable, Equatable, Sendable {
    public let isVisible: Bool
    public let sizeMultiplier: Double
    public let smoothing: CursorSmoothingLevel
    public let clickStyle: CursorClickStyle
    public let clickColor: CursorRGBAColor
    public let clickSize: Double
    public let clickDuration: TimeInterval
    public let spotlight: CursorSpotlightOptions?

    public static let standard = CursorRenderOptions(
        uncheckedIsVisible: true,
        sizeMultiplier: 1,
        smoothing: .off,
        clickStyle: .none,
        clickColor: .accent,
        clickSize: 1,
        clickDuration: 0.5,
        spotlight: nil
    )

    public static func standard(
        isVisible: Bool,
        clickStyle: CursorClickStyle
    ) -> CursorRenderOptions {
        CursorRenderOptions(
            uncheckedIsVisible: isVisible,
            sizeMultiplier: 1,
            smoothing: .off,
            clickStyle: clickStyle,
            clickColor: .accent,
            clickSize: 1,
            clickDuration: 0.5,
            spotlight: nil
        )
    }

    public init(
        isVisible: Bool = true,
        sizeMultiplier: Double = 1,
        smoothing: CursorSmoothingLevel = .off,
        clickStyle: CursorClickStyle = .none,
        clickColor: CursorRGBAColor = .accent,
        clickSize: Double = 1,
        clickDuration: TimeInterval = 0.5,
        spotlight: CursorSpotlightOptions? = nil
    ) throws {
        guard sizeMultiplier.isFinite, (1...4).contains(sizeMultiplier) else {
            throw CursorEffectModelError.invalidRenderOption
        }

        guard clickSize.isFinite, clickSize > 0 else {
            throw CursorEffectModelError.invalidRenderOption
        }

        guard clickDuration.isFinite, clickDuration >= 0 else {
            throw CursorEffectModelError.invalidRenderOption
        }

        self.init(
            uncheckedIsVisible: isVisible,
            sizeMultiplier: sizeMultiplier,
            smoothing: smoothing,
            clickStyle: clickStyle,
            clickColor: clickColor,
            clickSize: clickSize,
            clickDuration: clickDuration,
            spotlight: spotlight
        )
    }

    private init(
        uncheckedIsVisible isVisible: Bool,
        sizeMultiplier: Double,
        smoothing: CursorSmoothingLevel,
        clickStyle: CursorClickStyle,
        clickColor: CursorRGBAColor,
        clickSize: Double,
        clickDuration: TimeInterval,
        spotlight: CursorSpotlightOptions?
    ) {
        self.isVisible = isVisible
        self.sizeMultiplier = sizeMultiplier
        self.smoothing = smoothing
        self.clickStyle = clickStyle
        self.clickColor = clickColor
        self.clickSize = clickSize
        self.clickDuration = clickDuration
        self.spotlight = spotlight
    }
}

public enum CursorSmoothingLevel: String, Codable, CaseIterable, Equatable, Sendable {
    case off
    case light
    case medium
}

public enum CursorClickStyle: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case ringRipple
    case filledPulse
}

public struct CursorRGBAColor: Codable, Equatable, Sendable {
    public static let accent = CursorRGBAColor(uncheckedRed: 0.24, green: 0.48, blue: 1, alpha: 1)
    public static let black = CursorRGBAColor(uncheckedRed: 0, green: 0, blue: 0, alpha: 1)

    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) throws {
        guard [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw CursorEffectModelError.invalidColor
        }

        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    private init(uncheckedRed red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct CursorSpotlightOptions: Codable, Equatable, Sendable {
    public let radius: Double
    public let dimOpacity: Double
    public let dimColor: CursorRGBAColor
    public let feather: Double

    public init(
        radius: Double,
        dimOpacity: Double,
        dimColor: CursorRGBAColor = .black,
        feather: Double = 0.25
    ) throws {
        guard radius.isFinite, radius > 0 else {
            throw CursorEffectModelError.invalidRenderOption
        }

        guard dimOpacity.isFinite, (0...1).contains(dimOpacity) else {
            throw CursorEffectModelError.invalidRenderOption
        }

        guard feather.isFinite, (0...1).contains(feather) else {
            throw CursorEffectModelError.invalidRenderOption
        }

        self.radius = radius
        self.dimOpacity = dimOpacity
        self.dimColor = dimColor
        self.feather = feather
    }
}

public struct MediaPauseInterval: Codable, Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) throws {
        guard start.isFinite, end.isFinite, start >= 0, end > start else {
            throw CursorEffectModelError.invalidPauseInterval
        }

        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end - start
    }
}

public struct MediaTimeMapper: Codable, Equatable, Sendable {
    public let recordingDuration: TimeInterval
    public let pauses: [MediaPauseInterval]

    public init(recordingDuration: TimeInterval, pauses: [MediaPauseInterval] = []) throws {
        guard recordingDuration.isFinite, recordingDuration >= 0 else {
            throw CursorEffectModelError.invalidRecordingDuration
        }

        try Self.validatePauses(pauses, recordingDuration: recordingDuration)

        self.recordingDuration = recordingDuration
        self.pauses = pauses
    }

    public var mediaDuration: TimeInterval {
        pauses.reduce(recordingDuration) { duration, pause in
            duration - pause.duration
        }
    }

    public func mediaTime(forWallTime wallTime: TimeInterval) -> TimeInterval? {
        guard wallTime.isFinite, (0...recordingDuration).contains(wallTime) else {
            return nil
        }

        var removedDuration: TimeInterval = 0
        for pause in pauses {
            if wallTime >= pause.end {
                removedDuration += pause.duration
            } else if wallTime >= pause.start {
                return nil
            } else {
                break
            }
        }

        return wallTime - removedDuration
    }

    private static func validatePauses(
        _ pauses: [MediaPauseInterval],
        recordingDuration: TimeInterval
    ) throws {
        for pause in pauses where pause.end > recordingDuration {
            throw CursorEffectModelError.invalidPauseInterval
        }

        for pair in zip(pauses, pauses.dropFirst()) {
            if pair.1.start < pair.0.start {
                throw CursorEffectModelError.unsortedEvents
            }

            if pair.1.start < pair.0.end {
                throw CursorEffectModelError.overlappingPauseIntervals
            }
        }
    }
}

public struct SpotlightInterval: Codable, Equatable, Sendable {
    public let timeRange: TimeRange

    public init(timeRange: TimeRange) {
        self.timeRange = timeRange
    }
}

public enum SpotlightIntervalResolver {
    public static func intervals(
        from toggles: [TimeInterval],
        recordingDuration: TimeInterval
    ) throws -> [SpotlightInterval] {
        guard recordingDuration.isFinite, recordingDuration >= 0 else {
            throw CursorEffectModelError.invalidRecordingDuration
        }

        try CursorTimeline.validateSorted(toggles)
        for toggle in toggles where toggle > recordingDuration {
            throw CursorEffectModelError.invalidTime
        }

        var intervals: [SpotlightInterval] = []
        var activeStart: TimeInterval?
        for toggle in toggles {
            if let start = activeStart {
                if toggle > start {
                    intervals.append(SpotlightInterval(timeRange: try TimeRange(start: start, end: toggle)))
                }
                activeStart = nil
            } else {
                activeStart = toggle
            }
        }

        if let start = activeStart, recordingDuration > start {
            intervals.append(
                SpotlightInterval(timeRange: try TimeRange(start: start, end: recordingDuration)))
        }

        return intervals
    }
}

public enum CursorEffectModelError: Error, Equatable {
    case unsupportedSchemaVersion
    case unsupportedSidecarSchemaVersion
    case invalidPoint
    case invalidCursorImage
    case duplicateCursorImageID
    case missingCursorImage
    case invalidScale
    case invalidTime
    case unsortedEvents
    case invalidColor
    case invalidRenderOption
    case invalidPauseInterval
    case overlappingPauseIntervals
    case invalidRecordingDuration
}
