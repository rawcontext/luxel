import Foundation

public enum CursorMode: String, Codable, CaseIterable, Equatable, Sendable {
    case baked
    case editable
    case hidden
}

public struct CursorPoint: Codable, Equatable, Sendable {
    public let xCoordinate: Double
    public let yCoordinate: Double

    public init(x xCoordinate: Double, y yCoordinate: Double) throws {
        guard xCoordinate.isFinite, yCoordinate.isFinite else {
            throw CursorEffectModelError.invalidPoint
        }

        self.xCoordinate = xCoordinate
        self.yCoordinate = yCoordinate
    }

    private enum CodingKeys: String, CodingKey {
        case xCoordinate = "x"
        case yCoordinate = "y"
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
    case released = "up"
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

    static func validateSorted(_ times: [TimeInterval]) throws {
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
