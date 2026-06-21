import Foundation
import LuxelCore
import Testing

@Suite("Keystroke models")
struct KeystrokeModelTests {
    @Test("event normalizes characters and stores modifier metadata")
    func eventNormalizesCharactersAndStoresModifierMetadata() throws {
        let event = try KeystrokeEvent(
            time: 1.25,
            kind: .keyDown,
            keyCode: 40,
            characters: "k",
            modifiers: [.command, .shift],
            isRepeat: true
        )
        let emptyCharacters = try KeystrokeEvent(
            time: 1.5,
            kind: .flagsChanged,
            keyCode: 55,
            characters: ""
        )

        #expect(event.time == 1.25)
        #expect(event.kind == .keyDown)
        #expect(event.keyCode == 40)
        #expect(event.characters == "k")
        #expect(event.modifiers == [.command, .shift])
        #expect(event.isRepeat)
        #expect(emptyCharacters.characters == nil)
        #expect(KeystrokeModifier.command.displaySymbol == "⌘")
        #expect(KeystrokeModifier.shift.displaySymbol == "⇧")

        #expect(throws: KeystrokeModelError.invalidEventTime) {
            _ = try KeystrokeEvent(time: -1, kind: .keyDown, keyCode: 1)
        }
        #expect(throws: KeystrokeModelError.invalidEventTime) {
            _ = try KeystrokeEvent(time: .infinity, kind: .keyDown, keyCode: 1)
        }
        #expect(throws: KeystrokeModelError.invalidKeyCode) {
            _ = try KeystrokeEvent(time: 0, kind: .keyDown, keyCode: -1)
        }
    }

    @Test("timeline validates sorted events and non-overlapping pauses")
    func timelineValidatesSortedEventsAndPauses() throws {
        let first = try event(time: 1, keyCode: 4)
        let second = try event(time: 2, keyCode: 5)
        let pause = try KeystrokePauseInterval(
            timeRange: TimeRange(start: 3, end: 4),
            cause: .secureInput
        )

        let timeline = try KeystrokeTimeline(events: [first, second], pauses: [pause])

        #expect(timeline.schemaVersion == KeystrokeTimeline.currentSchemaVersion)
        #expect(timeline.events == [first, second])
        #expect(timeline.pauses == [pause])

        #expect(throws: KeystrokeModelError.unsupportedSchemaVersion) {
            _ = try KeystrokeTimeline(schemaVersion: 2)
        }
        #expect(throws: KeystrokeModelError.unsortedEvents) {
            _ = try KeystrokeTimeline(events: [second, first])
        }
        #expect(throws: KeystrokeModelError.unsortedPauses) {
            _ = try KeystrokeTimeline(pauses: [
                KeystrokePauseInterval(timeRange: TimeRange(start: 5, end: 6), cause: .user),
                KeystrokePauseInterval(timeRange: TimeRange(start: 2, end: 3), cause: .secureInput)
            ])
        }
        #expect(throws: KeystrokeModelError.overlappingPauses) {
            _ = try KeystrokeTimeline(pauses: [
                KeystrokePauseInterval(timeRange: TimeRange(start: 2, end: 5), cause: .user),
                KeystrokePauseInterval(timeRange: TimeRange(start: 4, end: 6), cause: .secureInput)
            ])
        }
    }

    @Test("timeline filters events inside pause windows")
    func timelineFiltersEventsInsidePauseWindows() throws {
        let visibleBeforePause = try event(time: 1, keyCode: 4)
        let hiddenDuringPause = try event(time: 2.5, keyCode: 5)
        let visibleAtPauseEnd = try event(time: 4, keyCode: 6)
        let timeline = try KeystrokeTimeline(
            events: [visibleBeforePause, hiddenDuringPause, visibleAtPauseEnd],
            pauses: [
                KeystrokePauseInterval(
                    timeRange: TimeRange(start: 2, end: 4),
                    cause: .secureInput
                )
            ]
        )

        #expect(timeline.eventsOutsidePauses() == [visibleBeforePause, visibleAtPauseEnd])
    }

    @Test("render options expose defaults and validate display duration")
    func renderOptionsExposeDefaultsAndValidateDisplayDuration() throws {
        let defaults = try KeystrokeRenderOptions()
        let custom = try KeystrokeRenderOptions(
            isVisible: false,
            anchor: .topRight,
            size: .large,
            theme: .highContrast,
            displayDuration: 2
        )

        #expect(defaults.isVisible)
        #expect(defaults.anchor == .bottomCenter)
        #expect(defaults.size == .medium)
        #expect(defaults.theme == .darkGlass)
        #expect(defaults.displayDuration == 1.5)
        #expect(KeystrokeRenderOptions.standard == defaults)
        #expect(!custom.isVisible)
        #expect(custom.anchor == .topRight)
        #expect(custom.size == .large)
        #expect(custom.theme == .highContrast)
        #expect(custom.displayDuration == 2)

        #expect(throws: KeystrokeModelError.invalidDisplayDuration) {
            _ = try KeystrokeRenderOptions(displayDuration: 0.49)
        }
        #expect(throws: KeystrokeModelError.invalidDisplayDuration) {
            _ = try KeystrokeRenderOptions(displayDuration: 5.01)
        }
        #expect(throws: KeystrokeModelError.invalidDisplayDuration) {
            _ = try KeystrokeRenderOptions(displayDuration: .infinity)
        }
    }

    @Test("timeline round trips through JSON sidecar encoding")
    func timelineRoundTripsThroughJSONSidecarEncoding() throws {
        let timeline = try KeystrokeTimeline(
            events: [
                KeystrokeEvent(
                    time: 1,
                    kind: .keyDown,
                    keyCode: 0,
                    characters: "a",
                    modifiers: [.shift]
                )
            ],
            pauses: [
                KeystrokePauseInterval(timeRange: TimeRange(start: 2, end: 3), cause: .user)
            ]
        )

        let data = try JSONEncoder().encode(timeline)
        let decoded = try JSONDecoder().decode(KeystrokeTimeline.self, from: data)

        #expect(decoded == timeline)
    }

    @Test("chip planner renders shortcuts and modifier holds")
    func chipPlannerRendersShortcutsAndModifierHolds() throws {
        let timeline = try KeystrokeTimeline(events: [
            flagsChanged(time: 0, modifiers: [.command]),
            flagsChanged(time: 0.75, modifiers: []),
            keyDown(time: 2, keyCode: 40, characters: "k", modifiers: [.command, .shift])
        ])

        let chips = try KeystrokeChipPlanner().plannedChips(for: timeline)

        #expect(chips.map(\.text) == ["⌘", "⌘⇧K"])
        #expect(chips.map(\.kind) == [.modifier, .shortcut])
        try #require(chips.count == 2)
        expectRange(chips[0].timeRange, start: 0.5, end: 2.25)
        expectRange(chips[1].timeRange, start: 2, end: 3.5)
    }

    @Test("chip planner coalesces typing caps text and splits after gaps")
    func chipPlannerCoalescesTypingCapsTextAndSplitsAfterGaps() throws {
        let letters = Array("abcdefghijklmnopqrstuvwxyz")
        let events =
            try letters.enumerated().map { index, character in
                try keyDown(
                    time: TimeInterval(index) / 10,
                    keyCode: index,
                    characters: String(character)
                )
            } + [
                keyDown(time: 4, keyCode: 18, characters: "!", modifiers: [.shift])
            ]
        let timeline = try KeystrokeTimeline(events: events)

        let chips = try KeystrokeChipPlanner().plannedChips(for: timeline)

        #expect(chips.map(\.text) == ["…hijklmnopqrstuvwxyz", "!"])
        #expect(chips.map(\.kind) == [.typing, .typing])
        try #require(chips.count == 2)
        expectRange(chips[0].timeRange, start: 0, end: 4)
        expectRange(chips[1].timeRange, start: 4, end: 5.5)
    }

    @Test("chip planner collapses repeats and hides paused events")
    func chipPlannerCollapsesRepeatsAndHidesPausedEvents() throws {
        let repeatEvents = try (0..<11).map { offset in
            try keyDown(
                time: 1.05 + TimeInterval(offset) * 0.05,
                keyCode: 123,
                isRepeat: true
            )
        }
        let timeline = try KeystrokeTimeline(
            events: [
                keyDown(time: 0.1, keyCode: 0, characters: "a"),
                keyDown(time: 0.3, keyCode: 11, characters: "b"),
                keyDown(time: 1, keyCode: 123)
            ] + repeatEvents,
            pauses: [
                KeystrokePauseInterval(
                    timeRange: TimeRange(start: 0.2, end: 0.4),
                    cause: .secureInput
                )
            ]
        )

        let chips = try KeystrokeChipPlanner().plannedChips(for: timeline)

        #expect(chips.map(\.text) == ["a", "←×12"])
        #expect(chips.map(\.kind) == [.typing, .special])
        try #require(chips.count == 2)
        expectRange(chips[0].timeRange, start: 0.1, end: 1.6)
        expectRange(chips[1].timeRange, start: 1, end: 2.5)
    }

    @Test("chip planner trims oldest overlapping chip at stack limit")
    func chipPlannerTrimsOldestOverlappingChipAtStackLimit() throws {
        let renderOptions = try KeystrokeRenderOptions(displayDuration: 2)
        let rules = try KeystrokeChipPlannerRules(maxVisibleChips: 3)
        let timeline = try KeystrokeTimeline(events: [
            keyDown(time: 0, keyCode: 0, characters: "a", modifiers: [.command]),
            keyDown(time: 0.1, keyCode: 1, characters: "b", modifiers: [.command]),
            keyDown(time: 0.2, keyCode: 2, characters: "c", modifiers: [.command]),
            keyDown(time: 0.3, keyCode: 3, characters: "d", modifiers: [.command])
        ])

        let chips = try KeystrokeChipPlanner(
            renderOptions: renderOptions,
            rules: rules
        ).plannedChips(for: timeline)

        #expect(chips.map(\.text) == ["⌘A", "⌘B", "⌘C", "⌘D"])
        try #require(chips.count == 4)
        expectRange(chips[0].timeRange, start: 0, end: 0.3)
        expectRange(chips[1].timeRange, start: 0.1, end: 2.1)
        expectRange(chips[2].timeRange, start: 0.2, end: 2.2)
        expectRange(chips[3].timeRange, start: 0.3, end: 2.3)
    }

    @Test("chip planner validates rules chips and disabled rendering")
    func chipPlannerValidatesRulesChipsAndDisabledRendering() throws {
        let hiddenOptions = try KeystrokeRenderOptions(isVisible: false)
        let timeline = try KeystrokeTimeline(events: [
            keyDown(time: 0, keyCode: 0, characters: "a")
        ])

        let chips = try KeystrokeChipPlanner(renderOptions: hiddenOptions)
            .plannedChips(for: timeline)

        #expect(chips.isEmpty)
        #expect(throws: KeystrokeModelError.invalidChipPlannerRules) {
            _ = try KeystrokeChipPlannerRules(maxVisibleChips: 0)
        }
        #expect(throws: KeystrokeModelError.invalidChipText) {
            _ = try KeystrokeChip(
                timeRange: TimeRange(start: 0, end: 1),
                text: " ",
                kind: .typing
            )
        }
    }

    private func event(time: TimeInterval, keyCode: Int) throws -> KeystrokeEvent {
        try KeystrokeEvent(time: time, kind: .keyDown, keyCode: keyCode)
    }

    private func keyDown(
        time: TimeInterval,
        keyCode: Int,
        characters: String? = nil,
        modifiers: Set<KeystrokeModifier> = [],
        isRepeat: Bool = false
    ) throws -> KeystrokeEvent {
        try KeystrokeEvent(
            time: time,
            kind: .keyDown,
            keyCode: keyCode,
            characters: characters,
            modifiers: modifiers,
            isRepeat: isRepeat
        )
    }

    private func flagsChanged(
        time: TimeInterval,
        modifiers: Set<KeystrokeModifier>
    ) throws -> KeystrokeEvent {
        try KeystrokeEvent(
            time: time,
            kind: .flagsChanged,
            keyCode: 55,
            modifiers: modifiers
        )
    }

    private func expectRange(
        _ range: TimeRange,
        start: TimeInterval,
        end: TimeInterval
    ) {
        #expect(abs(range.start - start) < 0.000_001)
        #expect(abs(range.end - end) < 0.000_001)
    }
}
