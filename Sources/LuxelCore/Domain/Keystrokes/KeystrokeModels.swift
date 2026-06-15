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

public struct KeystrokeSidecarDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let timeline: KeystrokeTimeline

    public init(
        schemaVersion: Int = KeystrokeSidecarDocument.currentSchemaVersion,
        timeline: KeystrokeTimeline
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw KeystrokeModelError.unsupportedSidecarSchemaVersion
        }

        self.schemaVersion = schemaVersion
        self.timeline = timeline
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == Self.currentSchemaVersion else {
            throw KeystrokeModelError.unsupportedSidecarSchemaVersion
        }

        self.schemaVersion = schemaVersion
        self.timeline = try container.decode(KeystrokeTimeline.self, forKey: .timeline)
    }
}

public struct KeystrokeRenderOptions: Codable, Equatable, Sendable {
    public let isVisible: Bool
    public let anchor: KeystrokeOverlayAnchor
    public let size: KeystrokeOverlaySize
    public let theme: KeystrokeOverlayTheme
    public let displayDuration: TimeInterval

    public static let standard = KeystrokeRenderOptions(
        uncheckedIsVisible: true,
        anchor: .bottomCenter,
        size: .medium,
        theme: .darkGlass,
        displayDuration: 1.5
    )

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

        self.init(
            uncheckedIsVisible: isVisible,
            anchor: anchor,
            size: size,
            theme: theme,
            displayDuration: displayDuration
        )
    }

    private init(
        uncheckedIsVisible isVisible: Bool,
        anchor: KeystrokeOverlayAnchor,
        size: KeystrokeOverlaySize,
        theme: KeystrokeOverlayTheme,
        displayDuration: TimeInterval
    ) {
        self.isVisible = isVisible
        self.anchor = anchor
        self.size = size
        self.theme = theme
        self.displayDuration = displayDuration
    }
}

public struct KeystrokeChip: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let text: String
    public let kind: KeystrokeChipKind

    public init(timeRange: TimeRange, text: String, kind: KeystrokeChipKind) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KeystrokeModelError.invalidChipText
        }

        self.timeRange = timeRange
        self.text = text
        self.kind = kind
    }
}

public enum KeystrokeChipKind: String, Codable, CaseIterable, Equatable, Sendable {
    case typing
    case shortcut
    case special
    case modifier
}

public struct KeystrokeChipPlannerRules: Equatable, Sendable {
    public let typingCoalescingInterval: TimeInterval
    public let maxTypingCharacters: Int
    public let modifierHoldThreshold: TimeInterval
    public let repeatCollapseThreshold: Int
    public let maxVisibleChips: Int

    public static let standard = KeystrokeChipPlannerRules(
        uncheckedTypingCoalescingInterval: 1,
        maxTypingCharacters: 20,
        modifierHoldThreshold: 0.5,
        repeatCollapseThreshold: 4,
        maxVisibleChips: 3
    )

    public init(
        typingCoalescingInterval: TimeInterval = 1,
        maxTypingCharacters: Int = 20,
        modifierHoldThreshold: TimeInterval = 0.5,
        repeatCollapseThreshold: Int = 4,
        maxVisibleChips: Int = 3
    ) throws {
        guard typingCoalescingInterval >= 0,
              typingCoalescingInterval.isFinite,
              maxTypingCharacters > 0,
              modifierHoldThreshold >= 0,
              modifierHoldThreshold.isFinite,
              repeatCollapseThreshold > 0,
              maxVisibleChips > 0 else {
            throw KeystrokeModelError.invalidChipPlannerRules
        }

        self.init(
            uncheckedTypingCoalescingInterval: typingCoalescingInterval,
            maxTypingCharacters: maxTypingCharacters,
            modifierHoldThreshold: modifierHoldThreshold,
            repeatCollapseThreshold: repeatCollapseThreshold,
            maxVisibleChips: maxVisibleChips
        )
    }

    private init(
        uncheckedTypingCoalescingInterval typingCoalescingInterval: TimeInterval,
        maxTypingCharacters: Int,
        modifierHoldThreshold: TimeInterval,
        repeatCollapseThreshold: Int,
        maxVisibleChips: Int
    ) {
        self.typingCoalescingInterval = typingCoalescingInterval
        self.maxTypingCharacters = maxTypingCharacters
        self.modifierHoldThreshold = modifierHoldThreshold
        self.repeatCollapseThreshold = repeatCollapseThreshold
        self.maxVisibleChips = maxVisibleChips
    }
}
