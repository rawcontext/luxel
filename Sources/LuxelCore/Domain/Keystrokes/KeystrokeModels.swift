import Foundation

public struct KeystrokeEvent: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let kind: KeystrokeEventKind
    public let keyCode: Int
    public let characters: String?
    public let modifiers: Set<KeystrokeModifier>
    public let isRepeat: Bool

    public init(
        time: TimeInterval,
        kind: KeystrokeEventKind,
        keyCode: Int,
        characters: String? = nil,
        modifiers: Set<KeystrokeModifier> = [],
        isRepeat: Bool = false
    ) throws {
        guard time.isFinite, time >= 0 else {
            throw KeystrokeModelError.invalidEventTime
        }

        guard keyCode >= 0 else {
            throw KeystrokeModelError.invalidKeyCode
        }

        self.time = time
        self.kind = kind
        self.keyCode = keyCode
        self.characters = Self.normalizedCharacters(characters)
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }

    private static func normalizedCharacters(_ characters: String?) -> String? {
        guard let characters, !characters.isEmpty else {
            return nil
        }

        return characters
    }
}

public enum KeystrokeEventKind: String, Codable, CaseIterable, Equatable, Sendable {
    case keyDown
    case flagsChanged
}

public enum KeystrokeModifier: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case command
    case shift
    case option
    case control
    case function

    public var displaySymbol: String {
        switch self {
        case .command:
            "⌘"
        case .shift:
            "⇧"
        case .option:
            "⌥"
        case .control:
            "⌃"
        case .function:
            "fn"
        }
    }
}

public struct KeystrokePauseInterval: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let cause: KeystrokePauseCause

    public init(timeRange: TimeRange, cause: KeystrokePauseCause) {
        self.timeRange = timeRange
        self.cause = cause
    }
}

public enum KeystrokePauseCause: String, Codable, CaseIterable, Equatable, Sendable {
    case user
    case secureInput
}

public struct KeystrokeTimeline: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let events: [KeystrokeEvent]
    public let pauses: [KeystrokePauseInterval]

    public init(
        schemaVersion: Int = KeystrokeTimeline.currentSchemaVersion,
        events: [KeystrokeEvent] = [],
        pauses: [KeystrokePauseInterval] = []
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw KeystrokeModelError.unsupportedSchemaVersion
        }

        try Self.validateSorted(events.map(\.time))
        try Self.validatePauses(pauses)

        self.schemaVersion = schemaVersion
        self.events = events
        self.pauses = pauses
    }

    public func eventsOutsidePauses() -> [KeystrokeEvent] {
        events.filter { event in
            !pauses.contains { pause in
                pause.timeRange.start <= event.time && event.time < pause.timeRange.end
            }
        }
    }

    private static func validateSorted(_ times: [TimeInterval]) throws {
        for time in times where !time.isFinite || time < 0 {
            throw KeystrokeModelError.invalidEventTime
        }

        for pair in zip(times, times.dropFirst()) where pair.1 < pair.0 {
            throw KeystrokeModelError.unsortedEvents
        }
    }

    private static func validatePauses(_ pauses: [KeystrokePauseInterval]) throws {
        for pair in zip(pauses, pauses.dropFirst()) {
            if pair.1.timeRange.start < pair.0.timeRange.start {
                throw KeystrokeModelError.unsortedPauses
            }

            if pair.1.timeRange.start < pair.0.timeRange.end {
                throw KeystrokeModelError.overlappingPauses
            }
        }
    }
}

public struct KeystrokeRenderOptions: Codable, Equatable, Sendable {
    public let isVisible: Bool
    public let anchor: KeystrokeOverlayAnchor
    public let size: KeystrokeOverlaySize
    public let theme: KeystrokeOverlayTheme
    public let displayDuration: TimeInterval

    public init(
        isVisible: Bool = true,
        anchor: KeystrokeOverlayAnchor = .bottomCenter,
        size: KeystrokeOverlaySize = .medium,
        theme: KeystrokeOverlayTheme = .darkGlass,
        displayDuration: TimeInterval = 1.5
    ) throws {
        guard displayDuration.isFinite, (0.5...5).contains(displayDuration) else {
            throw KeystrokeModelError.invalidDisplayDuration
        }

        self.isVisible = isVisible
        self.anchor = anchor
        self.size = size
        self.theme = theme
        self.displayDuration = displayDuration
    }
}

public enum KeystrokeOverlayAnchor: String, Codable, CaseIterable, Equatable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight
}

public enum KeystrokeOverlaySize: String, Codable, CaseIterable, Equatable, Sendable {
    case small
    case medium
    case large
}

public enum KeystrokeOverlayTheme: String, Codable, CaseIterable, Equatable, Sendable {
    case darkGlass
    case lightGlass
    case highContrast
}

public enum KeystrokeModelError: Error, Equatable {
    case unsupportedSchemaVersion
    case invalidEventTime
    case invalidKeyCode
    case unsortedEvents
    case unsortedPauses
    case overlappingPauses
    case invalidDisplayDuration
}
