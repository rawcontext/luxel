import AppIntents
import AppKit
import Foundation
import LuxelCore

enum LuxelShortcutCaptureTarget: String, AppEnum {
    case mainDisplay
    case activeWindow
    case lastArea

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Capture Target"

    static let caseDisplayRepresentations: [LuxelShortcutCaptureTarget: DisplayRepresentation] = [
        .mainDisplay: "Main Display",
        .activeWindow: "Active Window",
        .lastArea: "Last Area"
    ]

    var domainValue: AutomationShortcutCaptureTarget {
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
    var target: LuxelShortcutCaptureTarget

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
        target: LuxelShortcutCaptureTarget = .lastArea,
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
    var target: LuxelShortcutCaptureTarget?

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
        target: LuxelShortcutCaptureTarget? = nil,
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

enum LuxelShortcutScreenshotFormat: String, AppEnum {
    case png
    case jpeg
    case heic

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screenshot Format"

    static let caseDisplayRepresentations: [LuxelShortcutScreenshotFormat: DisplayRepresentation] = [
        .png: "PNG",
        .jpeg: "JPEG",
        .heic: "HEIC"
    ]

    var domainValue: ScreenshotFormat {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heic:
            .heic
        }
    }
}

struct LuxelRecordingEntity: AppEntity, Identifiable {
    struct Query: EntityStringQuery {
        func entities(for identifiers: [LuxelRecordingEntity.ID]) async throws -> [LuxelRecordingEntity] {
            let identifierSet = Set(identifiers)
            return Self.recordingEntities().filter { identifierSet.contains($0.id) }
        }

        func entities(matching string: String) async throws -> [LuxelRecordingEntity] {
            let normalizedQuery = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedQuery.isEmpty else {
                return try await suggestedEntities()
            }

            return Self.recordingEntities().filter { entity in
                entity.name.lowercased().contains(normalizedQuery)
                    || entity.fileName.lowercased().contains(normalizedQuery)
            }
        }

        func suggestedEntities() async throws -> [LuxelRecordingEntity] {
            Self.recordingEntities()
        }

        private static func recordingEntities() -> [LuxelRecordingEntity] {
            LuxelCompositionRoot.recordingHistoryService()
                .getPastRecordings(matching: .recordings)
                .map(LuxelRecordingEntity.init(recording:))
        }
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recording"
    static let defaultQuery = Query()

    let id: String
    let name: String
    let date: Date
    let kind: String
    let fileURL: URL
    let fileName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(fileName)"
        )
    }

    init(recording: PastRecording) {
        let mediaURL = recording.primaryMediaURL.standardizedFileURL

        id = mediaURL.path
        name = recording.name
        date = recording.date
        kind = recording.kind.rawValue
        fileURL = mediaURL
        fileName = mediaURL.lastPathComponent
    }
}

struct LuxelCaptureScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture Screenshot"
    static let description = IntentDescription("Captures a screenshot with Luxel.")
    static let openAppWhenRun = true

    @Parameter(title: "Target")
    var target: LuxelShortcutCaptureTarget

    @Parameter(title: "Format")
    var format: LuxelShortcutScreenshotFormat?

    init() {
        target = .mainDisplay
        format = nil
    }

    init(
        target: LuxelShortcutCaptureTarget = .mainDisplay,
        format: LuxelShortcutScreenshotFormat? = nil
    ) {
        self.target = target
        self.format = format
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.captureScreenshot(
            target: target.domainValue,
            format: format?.domainValue
        ))
        return .result()
    }
}

struct LuxelClipReplayBufferIntent: AppIntent {
    static let title: LocalizedStringResource = "Clip Replay Buffer"
    static let description = IntentDescription("Clips Luxel's replay buffer.")
    static let openAppWhenRun = true

    @Parameter(title: "Seconds")
    var seconds: Int?

    init() {
        seconds = nil
    }

    init(seconds: Int? = nil) {
        self.seconds = seconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        try LuxelAppIntentURLOpener.open(AutomationShortcutInvocationBuilder.clipReplayBuffer(
            seconds: seconds
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
            intent: LuxelCaptureScreenshotIntent(),
            phrases: [
                "Capture a screenshot with \(.applicationName)",
                "Take a screenshot with \(.applicationName)"
            ],
            shortTitle: "Capture Screenshot",
            systemImageName: "camera"
        )

        AppShortcut(
            intent: LuxelClipReplayBufferIntent(),
            phrases: [
                "Clip replay buffer with \(.applicationName)",
                "Clip the last moment with \(.applicationName)"
            ],
            shortTitle: "Clip Replay",
            systemImageName: "gobackward"
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
