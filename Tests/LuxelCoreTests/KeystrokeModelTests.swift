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

    private func event(time: TimeInterval, keyCode: Int) throws -> KeystrokeEvent {
        try KeystrokeEvent(time: time, kind: .keyDown, keyCode: keyCode)
    }
}
