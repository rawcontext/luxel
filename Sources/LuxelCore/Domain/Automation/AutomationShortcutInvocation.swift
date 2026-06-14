import Foundation

public enum AutomationShortcutCaptureTarget: String, CaseIterable, Equatable, Sendable {
    case mainDisplay
    case activeWindow
    case lastArea

    public var automationTarget: AutomationCaptureTarget {
        switch self {
        case .mainDisplay:
            .display(.main)
        case .activeWindow:
            .activeWindow
        case .lastArea:
            .lastArea
        }
    }
}

public enum AutomationShortcutInvocationBuilder {
    public static func startRecording(
        target: AutomationShortcutCaptureTarget,
        presetName: String? = nil,
        countdownSeconds: Int? = nil
    ) -> AutomationInvocation {
        AutomationInvocation(command: .record(AutomationRecordingOptions(
            target: target.automationTarget,
            presetName: nonEmpty(presetName),
            countdownSeconds: countdownSeconds
        )))
    }

    public static func toggleRecording(
        target: AutomationShortcutCaptureTarget? = nil,
        presetName: String? = nil,
        countdownSeconds: Int? = nil
    ) -> AutomationInvocation {
        AutomationInvocation(command: .toggle(target.map {
            AutomationRecordingOptions(
                target: $0.automationTarget,
                presetName: nonEmpty(presetName),
                countdownSeconds: countdownSeconds
            )
        }))
    }

    public static func stopRecording() -> AutomationInvocation {
        AutomationInvocation(command: .stop)
    }

    public static func clipReplayBuffer(seconds: Int? = nil) -> AutomationInvocation {
        AutomationInvocation(command: .clip(seconds: seconds))
    }

    public static func latestRecording(reveal: Bool = false) -> AutomationInvocation {
        AutomationInvocation(command: .latest(reveal: reveal))
    }

    public static func captureScreenshot(
        target: AutomationShortcutCaptureTarget,
        format: ScreenshotFormat? = nil
    ) -> AutomationInvocation {
        AutomationInvocation(command: .screenshot(AutomationScreenshotOptions(
            target: target.automationTarget,
            format: format
        )))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}
