import AppKit
import LuxelCore
import Testing

@testable import LuxelApp

@Suite("Keystroke live preview panel")
@MainActor
struct KeystrokeLivePreviewPanelControllerTests {
    @Test("capture exclusion registration precedes panel visibility")
    func captureExclusionRegistrationPrecedesVisibility() async throws {
        let eventLog = KeystrokePreviewEventLog()
        let controller = makeController(eventLog: eventLog)

        await controller.prepareForCapture(isEnabled: true)
        #expect(eventLog.events == ["register", "orderFront"])
        #expect(eventLog.orderedNonzeroPanel)

        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: 0, end: 1),
            text: "⌘K",
            kind: .shortcut
        )
        await controller.present(chips: [chip], options: .standard, isEnabled: true)
        await controller.present(chips: [chip], options: .standard, isEnabled: false)

        #expect(eventLog.events == ["register", "orderFront"])
        await controller.close()
    }

    @Test("live preview cannot create an unregistered panel after capture starts")
    func livePreviewRequiresCapturePreparation() async throws {
        let eventLog = KeystrokePreviewEventLog()
        let controller = makeController(eventLog: eventLog)
        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: 0, end: 1),
            text: "A",
            kind: .typing
        )

        await controller.present(chips: [chip], options: .standard, isEnabled: true)

        #expect(eventLog.events.isEmpty)
    }

    @Test("disabled live preview neither registers nor becomes visible")
    func disabledLivePreviewDoesNotRegisterOrBecomeVisible() async throws {
        let eventLog = KeystrokePreviewEventLog()
        let controller = makeController(eventLog: eventLog)

        await controller.prepareForCapture(isEnabled: false)
        let chip = try KeystrokeChip(
            timeRange: TimeRange(start: 0, end: 1),
            text: "A",
            kind: .typing
        )
        await controller.present(chips: [chip], options: .standard, isEnabled: false)

        #expect(eventLog.events.isEmpty)
    }

    private func makeController(
        eventLog: KeystrokePreviewEventLog
    ) -> KeystrokeLivePreviewPanelController {
        return KeystrokeLivePreviewPanelController(
            makePanel: {
                NSPanel(
                    contentRect: .zero,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
            },
            registerWindow: { _ in
                eventLog.append("register")
                return UUID()
            },
            unregisterWindow: { _ in
                eventLog.append("unregister")
            },
            orderFront: { panel in
                eventLog.orderedNonzeroPanel = panel.frame.width > 0 && panel.frame.height > 0
                eventLog.append("orderFront")
            }
        )
    }
}

@MainActor
private final class KeystrokePreviewEventLog {
    private(set) var events: [String] = []
    var orderedNonzeroPanel = false

    func append(_ event: String) {
        events.append(event)
    }
}
