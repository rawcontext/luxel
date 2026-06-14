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

public struct KeystrokeChipPlanner: Sendable {
    public let renderOptions: KeystrokeRenderOptions
    public let rules: KeystrokeChipPlannerRules

    public init(
        renderOptions: KeystrokeRenderOptions = .standard,
        rules: KeystrokeChipPlannerRules = .standard
    ) {
        self.renderOptions = renderOptions
        self.rules = rules
    }

    public func plannedChips(for timeline: KeystrokeTimeline) throws -> [KeystrokeChip] {
        guard renderOptions.isVisible else {
            return []
        }

        let events = timeline.eventsOutsidePauses()
        var plannedChips: [KeystrokeChip] = []
        var typingRun = TypingRun()
        var activeModifierHold: ModifierHold?
        var index = events.startIndex

        while index < events.endIndex {
            let event = events[index]

            switch event.kind {
            case .flagsChanged:
                try flushTypingRun(&typingRun, into: &plannedChips)
                try handleFlagsChanged(
                    event,
                    activeModifierHold: &activeModifierHold,
                    plannedChips: &plannedChips
                )
                index = events.index(after: index)

            case .keyDown:
                if let repeatGroup = repeatGroup(startingAt: index, in: events) {
                    try flushTypingRun(&typingRun, into: &plannedChips)
                    activeModifierHold = nil
                    try appendChip(
                        text: "\(repeatGroup.displayText)×\(repeatGroup.count)",
                        kind: repeatGroup.kind,
                        start: repeatGroup.start,
                        into: &plannedChips
                    )
                    index = repeatGroup.endIndex
                    continue
                }

                activeModifierHold = nil

                if let shortcutText = shortcutText(for: event) {
                    try flushTypingRun(&typingRun, into: &plannedChips)
                    try appendChip(
                        text: shortcutText,
                        kind: .shortcut,
                        start: event.time,
                        into: &plannedChips
                    )
                } else if let typingText = typingText(for: event) {
                    try appendTypingText(
                        typingText,
                        at: event.time,
                        typingRun: &typingRun,
                        plannedChips: &plannedChips
                    )
                } else if let specialText = specialText(for: event) {
                    try flushTypingRun(&typingRun, into: &plannedChips)
                    try appendChip(
                        text: specialText,
                        kind: .special,
                        start: event.time,
                        into: &plannedChips
                    )
                } else {
                    try flushTypingRun(&typingRun, into: &plannedChips)
                }

                index = events.index(after: index)
            }
        }

        try flushTypingRun(&typingRun, into: &plannedChips)
        try flushModifierHold(activeModifierHold, endingAt: events.last?.time, into: &plannedChips)
        return plannedChips
    }

    private func handleFlagsChanged(
        _ event: KeystrokeEvent,
        activeModifierHold: inout ModifierHold?,
        plannedChips: inout [KeystrokeChip]
    ) throws {
        guard !event.modifiers.isEmpty else {
            try flushModifierHold(activeModifierHold, endingAt: event.time, into: &plannedChips)
            activeModifierHold = nil
            return
        }

        if let activeModifierHold, activeModifierHold.modifiers != event.modifiers {
            try flushModifierHold(activeModifierHold, endingAt: event.time, into: &plannedChips)
        }
        activeModifierHold = ModifierHold(start: event.time, modifiers: event.modifiers)
    }

    private func flushModifierHold(
        _ hold: ModifierHold?,
        endingAt end: TimeInterval?,
        into plannedChips: inout [KeystrokeChip]
    ) throws {
        guard let hold, let end else {
            return
        }

        guard end - hold.start >= rules.modifierHoldThreshold else {
            return
        }

        try appendChip(
            text: modifierText(hold.modifiers),
            kind: .modifier,
            start: hold.start + rules.modifierHoldThreshold,
            into: &plannedChips,
            durationAnchor: end
        )
    }

    private func appendTypingText(
        _ text: String,
        at time: TimeInterval,
        typingRun: inout TypingRun,
        plannedChips: inout [KeystrokeChip]
    ) throws {
        if let lastTime = typingRun.lastTime,
           time - lastTime > rules.typingCoalescingInterval {
            try flushTypingRun(&typingRun, into: &plannedChips)
        }

        if typingRun.start == nil {
            typingRun.start = time
        }
        typingRun.lastTime = time
        typingRun.text += text
    }

    private func flushTypingRun(
        _ typingRun: inout TypingRun,
        into plannedChips: inout [KeystrokeChip]
    ) throws {
        guard let start = typingRun.start else {
            return
        }

        try appendChip(
            text: cappedTypingText(typingRun.text),
            kind: .typing,
            start: start,
            into: &plannedChips,
            durationAnchor: typingRun.lastTime ?? start
        )
        typingRun = TypingRun()
    }

    private func repeatGroup(
        startingAt index: [KeystrokeEvent].Index,
        in events: [KeystrokeEvent]
    ) -> RepeatGroup? {
        let event = events[index]
        guard event.kind == .keyDown,
              let displayText = specialText(for: event) ?? typingText(for: event) else {
            return nil
        }

        var groupEndIndex = events.index(after: index)
        var repeatCount = 0

        while groupEndIndex < events.endIndex {
            let next = events[groupEndIndex]
            guard next.kind == .keyDown,
                  next.isRepeat,
                  next.keyCode == event.keyCode,
                  (specialText(for: next) ?? typingText(for: next)) == displayText else {
                break
            }

            repeatCount += 1
            groupEndIndex = events.index(after: groupEndIndex)
        }

        guard repeatCount >= rules.repeatCollapseThreshold else {
            return nil
        }

        return RepeatGroup(
            displayText: displayText,
            kind: specialText(for: event) == nil ? .typing : .special,
            count: repeatCount + 1,
            start: event.time,
            endIndex: groupEndIndex
        )
    }

    private func shortcutText(for event: KeystrokeEvent) -> String? {
        guard event.kind == .keyDown,
              !event.modifiers.subtracting([.shift]).isEmpty,
              let keyText = specialText(for: event) ?? characterText(for: event) else {
            return nil
        }

        return modifierText(event.modifiers) + keyText.uppercased()
    }

    private func characterText(for event: KeystrokeEvent) -> String? {
        guard let characters = event.characters,
              !characters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return characters
    }

    private func typingText(for event: KeystrokeEvent) -> String? {
        guard event.kind == .keyDown,
              event.modifiers.subtracting([.shift]).isEmpty,
              specialText(for: event) == nil,
              let characters = characterText(for: event) else {
            return nil
        }

        return characters
    }

    private func specialText(for event: KeystrokeEvent) -> String? {
        switch event.keyCode {
        case 36:
            "⏎"
        case 48:
            "⇥"
        case 49:
            "␣"
        case 51:
            "⌫"
        case 53:
            "⎋"
        case 117:
            "⌦"
        case 123:
            "←"
        case 124:
            "→"
        case 125:
            "↓"
        case 126:
            "↑"
        default:
            nil
        }
    }

    private func modifierText(_ modifiers: Set<KeystrokeModifier>) -> String {
        modifierDisplayOrder
            .filter { modifiers.contains($0) }
            .map(\.displaySymbol)
            .joined()
    }

    private var modifierDisplayOrder: [KeystrokeModifier] {
        [.command, .shift, .option, .control, .function]
    }

    private func cappedTypingText(_ text: String) -> String {
        guard text.count > rules.maxTypingCharacters else {
            return text
        }

        let suffixLength = max(0, rules.maxTypingCharacters - 1)
        return "…" + text.suffix(suffixLength)
    }

    private func appendChip(
        text: String,
        kind: KeystrokeChipKind,
        start: TimeInterval,
        into plannedChips: inout [KeystrokeChip],
        durationAnchor: TimeInterval? = nil
    ) throws {
        let displayEnd = (durationAnchor ?? start) + renderOptions.displayDuration
        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: start, end: displayEnd),
            text: text,
            kind: kind
        )
        try appendWithStackLimit(chip, to: &plannedChips)
    }

    private func appendWithStackLimit(
        _ chip: KeystrokeChip,
        to plannedChips: inout [KeystrokeChip]
    ) throws {
        while activeChipIndexes(at: chip.timeRange.start, in: plannedChips).count >= rules.maxVisibleChips {
            guard let evictedIndex = activeChipIndexes(at: chip.timeRange.start, in: plannedChips).first else {
                break
            }

            let evicted = plannedChips[evictedIndex]
            if evicted.timeRange.start < chip.timeRange.start {
                plannedChips[evictedIndex] = try KeystrokeChip(
                    timeRange: TimeRange(start: evicted.timeRange.start, end: chip.timeRange.start),
                    text: evicted.text,
                    kind: evicted.kind
                )
            } else {
                plannedChips.remove(at: evictedIndex)
            }
        }

        plannedChips.append(chip)
    }

    private func activeChipIndexes(at time: TimeInterval, in plannedChips: [KeystrokeChip]) -> [Int] {
        plannedChips.indices.filter { index in
            plannedChips[index].timeRange.start <= time && time < plannedChips[index].timeRange.end
        }
    }

    private struct TypingRun {
        var start: TimeInterval?
        var lastTime: TimeInterval?
        var text = ""
    }

    private struct ModifierHold {
        let start: TimeInterval
        let modifiers: Set<KeystrokeModifier>
    }

    private struct RepeatGroup {
        let displayText: String
        let kind: KeystrokeChipKind
        let count: Int
        let start: TimeInterval
        let endIndex: [KeystrokeEvent].Index
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
    case unsupportedSidecarSchemaVersion
    case invalidEventTime
    case invalidKeyCode
    case unsortedEvents
    case unsortedPauses
    case overlappingPauses
    case invalidDisplayDuration
    case invalidChipText
    case invalidChipPlannerRules
}
