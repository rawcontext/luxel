import Foundation

public enum CursorMode: String, Codable, CaseIterable, Equatable, Sendable {
    case baked
    case editable
    case hidden
}

public struct CursorPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite else {
            throw CursorEffectModelError.invalidPoint
        }

        self.x = x
        self.y = y
    }
}

public struct CursorImageAsset: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let pngData: Data
    public let hotspot: CursorPoint
    public let scale: Double

    public init(
        id: String,
        pngData: Data,
        hotspot: CursorPoint,
        scale: Double
    ) throws {
        guard !id.isEmpty else {
            throw CursorEffectModelError.invalidCursorImage
        }

        guard !pngData.isEmpty else {
            throw CursorEffectModelError.invalidCursorImage
        }

        guard scale.isFinite, scale > 0 else {
            throw CursorEffectModelError.invalidScale
        }

        self.id = id
        self.pngData = pngData
        self.hotspot = hotspot
        self.scale = scale
    }
}

public struct CursorSample: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let position: CursorPoint
    public let cursorImageID: String

    public init(
        time: TimeInterval,
        position: CursorPoint,
        cursorImageID: String
    ) throws {
        guard Self.isValidTime(time) else {
            throw CursorEffectModelError.invalidTime
        }

        guard !cursorImageID.isEmpty else {
            throw CursorEffectModelError.missingCursorImage
        }

        self.time = time
        self.position = position
        self.cursorImageID = cursorImageID
    }

    private static func isValidTime(_ time: TimeInterval) -> Bool {
        time.isFinite && time >= 0
    }
}

public struct CursorClickEvent: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let button: CursorClickButton
    public let phase: CursorClickPhase

    public init(
        time: TimeInterval,
        button: CursorClickButton,
        phase: CursorClickPhase
    ) throws {
        guard time.isFinite, time >= 0 else {
            throw CursorEffectModelError.invalidTime
        }

        self.time = time
        self.button = button
        self.phase = phase
    }
}

public enum CursorClickButton: String, Codable, CaseIterable, Equatable, Sendable {
    case left
    case right
    case other
}

public enum CursorClickPhase: String, Codable, CaseIterable, Equatable, Sendable {
    case down
    case up
}

public struct CursorTimeline: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let samples: [CursorSample]
    public let clicks: [CursorClickEvent]
    public let spotlightToggles: [TimeInterval]
    public let cursorImages: [CursorImageAsset]

    public init(
        schemaVersion: Int = CursorTimeline.currentSchemaVersion,
        samples: [CursorSample] = [],
        clicks: [CursorClickEvent] = [],
        spotlightToggles: [TimeInterval] = [],
        cursorImages: [CursorImageAsset] = []
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CursorEffectModelError.unsupportedSchemaVersion
        }

        let imageIDs = try Self.validateImages(cursorImages)
        try Self.validateSorted(samples.map(\.time))
        try Self.validateSorted(clicks.map(\.time))
        try Self.validateSorted(spotlightToggles)
        try Self.validateSampleImages(samples, imageIDs: imageIDs)

        self.schemaVersion = schemaVersion
        self.samples = samples
        self.clicks = clicks
        self.spotlightToggles = spotlightToggles
        self.cursorImages = cursorImages
    }

    private static func validateImages(_ images: [CursorImageAsset]) throws -> Set<String> {
        var ids: Set<String> = []
        for image in images where !ids.insert(image.id).inserted {
            throw CursorEffectModelError.duplicateCursorImageID
        }

        return ids
    }

    fileprivate static func validateSorted(_ times: [TimeInterval]) throws {
        for time in times where !time.isFinite || time < 0 {
            throw CursorEffectModelError.invalidTime
        }

        for pair in zip(times, times.dropFirst()) where pair.1 < pair.0 {
            throw CursorEffectModelError.unsortedEvents
        }
    }

    private static func validateSampleImages(_ samples: [CursorSample], imageIDs: Set<String>) throws {
        for sample in samples where !imageIDs.contains(sample.cursorImageID) {
            throw CursorEffectModelError.missingCursorImage
        }
    }
}

public struct CursorSidecarDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let timeline: CursorTimeline

    public init(
        schemaVersion: Int = CursorSidecarDocument.currentSchemaVersion,
        timeline: CursorTimeline
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CursorEffectModelError.unsupportedSidecarSchemaVersion
        }

        self.schemaVersion = schemaVersion
        self.timeline = timeline
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw CursorEffectModelError.unsupportedSidecarSchemaVersion
        }

        self.schemaVersion = schemaVersion
        self.timeline = try container.decode(CursorTimeline.self, forKey: .timeline)
    }
}

public struct CursorRenderOptions: Codable, Equatable, Sendable {
    public let isVisible: Bool
    public let sizeMultiplier: Double
    public let smoothing: CursorSmoothingLevel
    public let clickStyle: CursorClickStyle
    public let clickColor: CursorRGBAColor
    public let clickSize: Double
    public let clickDuration: TimeInterval
    public let spotlight: CursorSpotlightOptions?

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
    public static let accent = try! CursorRGBAColor(red: 0.24, green: 0.48, blue: 1, alpha: 1)

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
}

public struct CursorSpotlightOptions: Codable, Equatable, Sendable {
    public let radius: Double
    public let dimOpacity: Double
    public let dimColor: CursorRGBAColor
    public let feather: Double

    public init(
        radius: Double,
        dimOpacity: Double,
        dimColor: CursorRGBAColor = try! CursorRGBAColor(red: 0, green: 0, blue: 0, alpha: 1),
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
            intervals.append(SpotlightInterval(timeRange: try TimeRange(start: start, end: recordingDuration)))
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
