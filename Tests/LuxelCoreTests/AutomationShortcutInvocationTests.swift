import LuxelCore
import Testing

@Suite("Automation shortcut invocation builder")
struct AutomationShortcutInvocationTests {
    @Test("start recording maps shortcut target preset and countdown")
    func startRecordingMapsShortcutTargetPresetAndCountdown() throws {
        let invocation = AutomationShortcutInvocationBuilder.startRecording(
            target: .mainDisplay,
            presetName: "Quick GIF",
            countdownSeconds: 3
        )

        #expect(invocation == AutomationInvocation(command: .record(AutomationRecordingOptions(
            target: .display(.main),
            presetName: "Quick GIF",
            countdownSeconds: 3
        ))))
        #expect(
            AutomationInvocationURLBuilder.url(for: invocation).absoluteString
                == "luxel://record?target=display&display=main&preset=Quick%20GIF&countdown=3"
        )
    }

    @Test("toggle can stop or start from a shortcut target")
    func toggleCanStopOrStartFromShortcutTarget() throws {
        let stopInvocation = AutomationShortcutInvocationBuilder.toggleRecording()
        let startInvocation = AutomationShortcutInvocationBuilder.toggleRecording(
            target: .activeWindow,
            presetName: "",
            countdownSeconds: 0
        )

        #expect(stopInvocation == AutomationInvocation(command: .toggle(nil)))
        #expect(startInvocation == AutomationInvocation(command: .toggle(AutomationRecordingOptions(
            target: .activeWindow,
            presetName: nil,
            countdownSeconds: 0
        ))))
        #expect(
            AutomationInvocationURLBuilder.url(for: startInvocation).absoluteString
                == "luxel://toggle?target=activeWindow&countdown=0"
        )
    }

    @Test("safe shortcut commands map to stop and latest recording")
    func safeShortcutCommandsMapToStopAndLatestRecording() {
        #expect(AutomationShortcutInvocationBuilder.stopRecording() == AutomationInvocation(command: .stop))
        #expect(
            AutomationShortcutInvocationBuilder.latestRecording(reveal: true)
                == AutomationInvocation(command: .latest(reveal: true))
        )
    }

    @Test("capture screenshot maps shortcut target and format")
    func captureScreenshotMapsShortcutTargetAndFormat() {
        let invocation = AutomationShortcutInvocationBuilder.captureScreenshot(
            target: .activeWindow,
            format: .heic
        )

        #expect(invocation == AutomationInvocation(command: .screenshot(AutomationScreenshotOptions(
            target: .activeWindow,
            format: .heic
        ))))
        #expect(
            AutomationInvocationURLBuilder.url(for: invocation).absoluteString
                == "luxel://screenshot?target=activeWindow&format=heic"
        )
    }
}
