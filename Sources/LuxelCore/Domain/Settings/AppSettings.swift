import Foundation

public enum AudioInputDeviceID {
    public static let systemDefault = "SYSTEM_DEFAULT"
}

public struct AudioInputDeviceOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public static let systemDefault = AudioInputDeviceOption(
        id: AudioInputDeviceID.systemDefault,
        name: "System Default"
    )
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static func defaults(recordingsDirectory: URL) -> AppSettings {
        AppSettings(recordingsDirectory: recordingsDirectory)
    }

    public var recordingsDirectory: URL
    public var recordingsDirectoryBookmark: BookmarkedDirectory?
    public var showCursor: Bool {
        didSet {
            cursorMode = Self.cursorMode(showCursor: showCursor)
            cursorRenderOptions = Self.cursorRenderOptions(
                showCursor: showCursor,
                highlightClicks: highlightClicks
            )
        }
    }
    public var highlightClicks: Bool {
        didSet {
            cursorRenderOptions = Self.cursorRenderOptions(
                showCursor: showCursor,
                highlightClicks: highlightClicks
            )
        }
    }
    public var cursorMode: CursorMode
    public var cursorRenderOptions: CursorRenderOptions
    public var record60FPS: Bool
    public var loopExports: Bool
    public var recordAudio: Bool
    public var audioInputDeviceID: String?
    public var audioInputDeviceName: String?
    public var audioOnlyFormat: AudioRecordingFormat
    public var enableShortcuts: Bool
    public var triggerCropperShortcut: String
    public var toggleRecordingShortcut: String
    public var recordActiveWindowShortcut: String
    public var recordFullscreenShortcut: String
    public var audioOnlyRecordingShortcut: String
    public var quickRecordLastShortcut: String
    public var captureScreenshotShortcut: String
    public var screenshotActiveWindowShortcut: String
    public var screenshotFullscreenShortcut: String
    public var updatePreferences: UpdatePreferences
    public var showTimeInMenuBar: Bool
    public var notificationReminder: Bool
    public var allowURLAutomation: Bool
    public var urlAutomationGrants: [String]
    public var exportPresets: [ExportPreset]
    public var quickExportPresetID: UUID?
    public var rememberLastCapture: Bool
    public var lastCaptureMemory: LastCaptureMemory?
    public var perFormatExportMemory: [ExportFormat: ExportMemory]
    public var screenshotFormat: ScreenshotFormat
    public var screenshotDestinations: [ScreenshotDestination]
    public var screenshotShowThumbnail: Bool
    public var screenshotBackdrop: CaptureBackdrop
    public var confirmDiscard: Bool
    public var lastStopAfter: TimeInterval?

    public init(
        recordingsDirectory: URL,
        recordingsDirectoryBookmark: BookmarkedDirectory? = nil,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        cursorMode: CursorMode? = nil,
        cursorRenderOptions: CursorRenderOptions? = nil,
        record60FPS: Bool = false,
        loopExports: Bool = true,
        recordAudio: Bool = false,
        audioInputDeviceID: String? = AudioInputDeviceID.systemDefault,
        audioInputDeviceName: String? = AudioInputDeviceOption.systemDefault.name,
        audioOnlyFormat: AudioRecordingFormat = .aac,
        enableShortcuts: Bool = true,
        triggerCropperShortcut: String = "",
        toggleRecordingShortcut: String = "",
        recordActiveWindowShortcut: String = "",
        recordFullscreenShortcut: String = "",
        audioOnlyRecordingShortcut: String = "",
        quickRecordLastShortcut: String = "",
        captureScreenshotShortcut: String = "",
        screenshotActiveWindowShortcut: String = "",
        screenshotFullscreenShortcut: String = "",
        updatePreferences: UpdatePreferences = .defaults,
        showTimeInMenuBar: Bool = true,
        notificationReminder: Bool = true,
        allowURLAutomation: Bool = false,
        urlAutomationGrants: [String] = [],
        exportPresets: [ExportPreset] = ExportPreset.builtInDefaults,
        quickExportPresetID: UUID? = ExportPreset.quickGIFID,
        rememberLastCapture: Bool = true,
        lastCaptureMemory: LastCaptureMemory? = nil,
        perFormatExportMemory: [ExportFormat: ExportMemory] = [:],
        screenshotFormat: ScreenshotFormat = .png,
        screenshotDestinations: [ScreenshotDestination] = [.clipboard, .file],
        screenshotShowThumbnail: Bool = true,
        screenshotBackdrop: CaptureBackdrop = .opaque,
        confirmDiscard: Bool = true,
        lastStopAfter: TimeInterval? = nil
    ) {
        self.recordingsDirectory = recordingsDirectory
        self.recordingsDirectoryBookmark = recordingsDirectoryBookmark
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.cursorMode = cursorMode ?? Self.cursorMode(showCursor: showCursor)
        self.cursorRenderOptions = cursorRenderOptions ?? Self.cursorRenderOptions(
            showCursor: showCursor,
            highlightClicks: highlightClicks
        )
        self.record60FPS = record60FPS
        self.loopExports = loopExports
        self.recordAudio = recordAudio
        self.audioInputDeviceID = audioInputDeviceID
        self.audioInputDeviceName = audioInputDeviceName
        self.audioOnlyFormat = audioOnlyFormat
        self.enableShortcuts = enableShortcuts
        self.triggerCropperShortcut = triggerCropperShortcut
        self.toggleRecordingShortcut = toggleRecordingShortcut
        self.recordActiveWindowShortcut = recordActiveWindowShortcut
        self.recordFullscreenShortcut = recordFullscreenShortcut
        self.audioOnlyRecordingShortcut = audioOnlyRecordingShortcut
        self.quickRecordLastShortcut = quickRecordLastShortcut
        self.captureScreenshotShortcut = captureScreenshotShortcut
        self.screenshotActiveWindowShortcut = screenshotActiveWindowShortcut
        self.screenshotFullscreenShortcut = screenshotFullscreenShortcut
        self.updatePreferences = updatePreferences
        self.showTimeInMenuBar = showTimeInMenuBar
        self.notificationReminder = notificationReminder
        self.allowURLAutomation = allowURLAutomation
        self.urlAutomationGrants = urlAutomationGrants
        self.exportPresets = exportPresets
        self.quickExportPresetID = quickExportPresetID
        self.rememberLastCapture = rememberLastCapture
        self.lastCaptureMemory = lastCaptureMemory
        self.perFormatExportMemory = perFormatExportMemory
        self.screenshotFormat = screenshotFormat
        self.screenshotDestinations = screenshotDestinations
        self.screenshotShowThumbnail = screenshotShowThumbnail
        self.screenshotBackdrop = screenshotBackdrop
        self.confirmDiscard = confirmDiscard
        self.lastStopAfter = lastStopAfter
    }

    private enum CodingKeys: String, CodingKey {
        case recordingsDirectory
        case recordingsDirectoryBookmark
        case showCursor
        case highlightClicks
        case cursorMode
        case cursorRenderOptions
        case record60FPS
        case loopExports
        case recordAudio
        case audioInputDeviceID
        case audioInputDeviceName
        case audioOnlyFormat
        case enableShortcuts
        case triggerCropperShortcut
        case toggleRecordingShortcut
        case recordActiveWindowShortcut
        case recordFullscreenShortcut
        case audioOnlyRecordingShortcut
        case quickRecordLastShortcut
        case captureScreenshotShortcut
        case screenshotActiveWindowShortcut
        case screenshotFullscreenShortcut
        case updatePreferences
        case showTimeInMenuBar
        case notificationReminder
        case allowURLAutomation
        case urlAutomationGrants
        case exportPresets
        case quickExportPresetID
        case rememberLastCapture
        case lastCaptureMemory
        case perFormatExportMemory
        case screenshotFormat
        case screenshotDestinations
        case screenshotShowThumbnail
        case screenshotBackdrop
        case confirmDiscard
        case lastStopAfter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultUpdatePreferences = UpdatePreferences.defaults

        recordingsDirectory = try container.decode(URL.self, forKey: .recordingsDirectory)
        recordingsDirectoryBookmark = try container.decodeIfPresent(
            BookmarkedDirectory.self,
            forKey: .recordingsDirectoryBookmark
        )
        showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor)
            ?? true
        highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks)
            ?? false
        cursorMode = try container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)
            ?? Self.cursorMode(showCursor: showCursor)
        cursorRenderOptions = try container.decodeIfPresent(
            CursorRenderOptions.self,
            forKey: .cursorRenderOptions
        ) ?? Self.cursorRenderOptions(showCursor: showCursor, highlightClicks: highlightClicks)
        record60FPS = try container.decodeIfPresent(Bool.self, forKey: .record60FPS)
            ?? false
        loopExports = try container.decodeIfPresent(Bool.self, forKey: .loopExports)
            ?? true
        recordAudio = try container.decodeIfPresent(Bool.self, forKey: .recordAudio)
            ?? false
        if container.contains(.audioInputDeviceID) {
            audioInputDeviceID = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceID)
        } else {
            audioInputDeviceID = AudioInputDeviceID.systemDefault
        }
        if container.contains(.audioInputDeviceName) {
            audioInputDeviceName = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceName)
        } else if audioInputDeviceID == AudioInputDeviceID.systemDefault {
            audioInputDeviceName = AudioInputDeviceOption.systemDefault.name
        } else {
            audioInputDeviceName = nil
        }
        audioOnlyFormat = try container.decodeIfPresent(AudioRecordingFormat.self, forKey: .audioOnlyFormat)
            ?? .aac
        enableShortcuts = try container.decodeIfPresent(Bool.self, forKey: .enableShortcuts)
            ?? true
        triggerCropperShortcut = try container.decodeIfPresent(String.self, forKey: .triggerCropperShortcut)
            ?? ""
        toggleRecordingShortcut = try container.decodeIfPresent(String.self, forKey: .toggleRecordingShortcut)
            ?? ""
        recordActiveWindowShortcut = try container.decodeIfPresent(String.self, forKey: .recordActiveWindowShortcut)
            ?? ""
        recordFullscreenShortcut = try container.decodeIfPresent(String.self, forKey: .recordFullscreenShortcut)
            ?? ""
        audioOnlyRecordingShortcut = try container.decodeIfPresent(String.self, forKey: .audioOnlyRecordingShortcut)
            ?? ""
        quickRecordLastShortcut = try container.decodeIfPresent(String.self, forKey: .quickRecordLastShortcut)
            ?? ""
        captureScreenshotShortcut = try container.decodeIfPresent(String.self, forKey: .captureScreenshotShortcut)
            ?? ""
        screenshotActiveWindowShortcut = try container.decodeIfPresent(String.self, forKey: .screenshotActiveWindowShortcut)
            ?? ""
        screenshotFullscreenShortcut = try container.decodeIfPresent(String.self, forKey: .screenshotFullscreenShortcut)
            ?? ""
        updatePreferences = try container.decodeIfPresent(UpdatePreferences.self, forKey: .updatePreferences)
            ?? defaultUpdatePreferences
        showTimeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showTimeInMenuBar)
            ?? true
        notificationReminder = try container.decodeIfPresent(Bool.self, forKey: .notificationReminder)
            ?? true
        allowURLAutomation = try container.decodeIfPresent(Bool.self, forKey: .allowURLAutomation)
            ?? false
        urlAutomationGrants = try container.decodeIfPresent([String].self, forKey: .urlAutomationGrants)
            ?? []
        exportPresets = try container.decodeIfPresent([ExportPreset].self, forKey: .exportPresets)
            ?? ExportPreset.builtInDefaults
        if container.contains(.quickExportPresetID) {
            quickExportPresetID = try container.decodeIfPresent(UUID.self, forKey: .quickExportPresetID)
        } else {
            quickExportPresetID = ExportPreset.quickGIFID
        }
        rememberLastCapture = try container.decodeIfPresent(Bool.self, forKey: .rememberLastCapture)
            ?? true
        lastCaptureMemory = try container.decodeIfPresent(LastCaptureMemory.self, forKey: .lastCaptureMemory)
        perFormatExportMemory = try container.decodeIfPresent(
            [ExportFormat: ExportMemory].self,
            forKey: .perFormatExportMemory
        ) ?? [:]
        screenshotFormat = try container.decodeIfPresent(ScreenshotFormat.self, forKey: .screenshotFormat)
            ?? .png
        screenshotDestinations = try container.decodeIfPresent(
            [ScreenshotDestination].self,
            forKey: .screenshotDestinations
        ) ?? [.clipboard, .file]
        screenshotShowThumbnail = try container.decodeIfPresent(Bool.self, forKey: .screenshotShowThumbnail)
            ?? true
        screenshotBackdrop = try container.decodeIfPresent(CaptureBackdrop.self, forKey: .screenshotBackdrop)
            ?? .opaque
        confirmDiscard = try container.decodeIfPresent(Bool.self, forKey: .confirmDiscard)
            ?? true
        lastStopAfter = try container.decodeIfPresent(TimeInterval.self, forKey: .lastStopAfter)
    }

    private static func cursorMode(showCursor: Bool) -> CursorMode {
        showCursor ? .baked : .hidden
    }

    private static func cursorRenderOptions(
        showCursor: Bool,
        highlightClicks: Bool
    ) -> CursorRenderOptions {
        try! CursorRenderOptions(
            isVisible: showCursor,
            clickStyle: highlightClicks ? .ringRipple : .none
        )
    }
}

public struct UpdatePreferences: Codable, Equatable, Sendable {
    public static let defaults = UpdatePreferences()

    public var automaticallyCheckForUpdates: Bool
    public var automaticallyDownloadAndInstall: Bool
    public var channel: UpdateChannel

    public init(
        automaticallyCheckForUpdates: Bool = true,
        automaticallyDownloadAndInstall: Bool = false,
        channel: UpdateChannel = .stable
    ) {
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.automaticallyDownloadAndInstall = automaticallyDownloadAndInstall
        self.channel = channel
    }
}

public enum UpdateChannel: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case stable
    case beta

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .stable:
            "Stable"
        case .beta:
            "Beta"
        }
    }
}
