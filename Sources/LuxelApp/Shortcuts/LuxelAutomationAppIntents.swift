import AppIntents
import AppKit
import Foundation
import LuxelCore

enum LuxelShortcutRecordingTarget: String, AppEnum {
    case mainDisplay
    case activeWindow
    case lastArea

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recording Target"

    static let caseDisplayRepresentations: [LuxelShortcutRecordingTarget: DisplayRepresentation] = [
        .mainDisplay: "Main Display",
        .activeWindow: "Active Window",
        .lastArea: "Last Area"
    ]

    var domainValue: AutomationShortcutRecordingTarget {
        switch self {
        case .mainDisplay:
            .mainDisplay
        case .activeWindow:
            .activeWindow
        case .lastArea:
            .lastArea
        }
    }
}

struct LuxelStartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Starts a Luxel screen recording.")
    static let openAppWhenRun = true

    @Parameter(title: "Target")
    var target: LuxelShortcutRecordingTarget

    @Parameter(title: "Preset")
    var presetName: String?

    @Parameter(title: "Countdown")
    var countdownSeconds: Int?

    init() {
        target = .lastArea
        presetName = nil
        countdownSeconds = nil
    }

    init(
        target: LuxelShortcutRecordingTarget = .lastArea,
        presetName: String? = nil,
        countdownSeconds: Int? = nil
    ) {
        self.target = target
        self.presetName = presetName
        self.countdownSeconds = countdownSeconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.startRecording(
            target: target.domainValue,
            presetName: presetName,
            countdownSeconds: countdownSeconds
        ))
        return .result()
    }
}

struct LuxelStopRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    static let description = IntentDescription("Stops the active Luxel recording.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.stopRecording())
        return .result()
    }
}

struct LuxelToggleRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Recording"
    static let description = IntentDescription("Stops the active recording, or starts one with the selected target.")
    static let openAppWhenRun = true

    @Parameter(title: "Target")
    var target: LuxelShortcutRecordingTarget?

    @Parameter(title: "Preset")
    var presetName: String?

    @Parameter(title: "Countdown")
    var countdownSeconds: Int?

    init() {
        target = nil
        presetName = nil
        countdownSeconds = nil
    }

    init(
        target: LuxelShortcutRecordingTarget? = nil,
        presetName: String? = nil,
        countdownSeconds: Int? = nil
    ) {
        self.target = target
        self.presetName = presetName
        self.countdownSeconds = countdownSeconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.toggleRecording(
            target: target?.domainValue,
            presetName: presetName,
            countdownSeconds: countdownSeconds
        ))
        return .result()
    }
}

struct LuxelOpenLatestRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Latest Recording"
    static let description = IntentDescription("Opens or reveals the latest Luxel recording.")
    static let openAppWhenRun = true

    @Parameter(title: "Reveal in Finder")
    var revealInFinder: Bool

    init() {
        revealInFinder = false
    }

    init(revealInFinder: Bool = false) {
        self.revealInFinder = revealInFinder
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.latestRecording(
            reveal: revealInFinder
        ))
        return .result()
    }
}

struct LuxelAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LuxelStartRecordingIntent(),
            phrases: [
                "Start a recording with \(.applicationName)",
                "Record my screen with \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "record.circle"
        )

        AppShortcut(
            intent: LuxelStopRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "Stop \(.applicationName)"
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.circle"
        )

        AppShortcut(
            intent: LuxelToggleRecordingIntent(),
            phrases: [
                "Toggle recording with \(.applicationName)",
                "Toggle \(.applicationName)"
            ],
            shortTitle: "Toggle Recording",
            systemImageName: "record.circle"
        )

        AppShortcut(
            intent: LuxelOpenLatestRecordingIntent(),
            phrases: [
                "Open latest recording with \(.applicationName)",
                "Show my latest \(.applicationName) recording"
            ],
            shortTitle: "Latest Recording",
            systemImageName: "film"
        )
    }
}

private enum LuxelAppIntentURLOpener {
    @MainActor
    static func open(_ invocation: AutomationInvocation) throws {
        let url = AutomationInvocationURLBuilder.url(for: invocation)
        guard NSWorkspace.shared.open(url) else {
            throw LuxelAppIntentError.openFailed(url)
        }
    }
}

private enum LuxelAppIntentError: LocalizedError {
    case openFailed(URL)

    var errorDescription: String? {
        switch self {
        case .openFailed(let url):
            "Failed to open \(url.absoluteString)."
        }
    }
}
