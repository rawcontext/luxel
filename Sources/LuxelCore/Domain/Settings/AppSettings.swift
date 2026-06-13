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
    public var showCursor: Bool
    public var highlightClicks: Bool
    public var record60FPS: Bool
    public var loopExports: Bool
    public var recordAudio: Bool
    public var audioInputDeviceID: String?
    public var audioInputDeviceName: String?
    public var audioOnlyFormat: AudioRecordingFormat
    public var enableShortcuts: Bool
    public var triggerCropperShortcut: String
    public var toggleRecordingShortcut: String
    public var audioOnlyRecordingShortcut: String
    public var quickRecordLastShortcut: String
    public var updatePreferences: UpdatePreferences
    public var showTimeInMenuBar: Bool
    public var exportPresets: [ExportPreset]
    public var quickExportPresetID: UUID?
    public var rememberLastCapture: Bool
    public var lastCaptureMemory: LastCaptureMemory?

    public init(
        recordingsDirectory: URL,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        record60FPS: Bool = false,
        loopExports: Bool = true,
        recordAudio: Bool = false,
        audioInputDeviceID: String? = AudioInputDeviceID.systemDefault,
        audioInputDeviceName: String? = AudioInputDeviceOption.systemDefault.name,
        audioOnlyFormat: AudioRecordingFormat = .aac,
        enableShortcuts: Bool = true,
        triggerCropperShortcut: String = "",
        toggleRecordingShortcut: String = "",
        audioOnlyRecordingShortcut: String = "",
        quickRecordLastShortcut: String = "",
        updatePreferences: UpdatePreferences = .defaults,
        showTimeInMenuBar: Bool = true,
        exportPresets: [ExportPreset] = ExportPreset.builtInDefaults,
        quickExportPresetID: UUID? = ExportPreset.quickGIFID,
        rememberLastCapture: Bool = true,
        lastCaptureMemory: LastCaptureMemory? = nil
    ) {
        self.recordingsDirectory = recordingsDirectory
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.record60FPS = record60FPS
        self.loopExports = loopExports
        self.recordAudio = recordAudio
        self.audioInputDeviceID = audioInputDeviceID
        self.audioInputDeviceName = audioInputDeviceName
        self.audioOnlyFormat = audioOnlyFormat
        self.enableShortcuts = enableShortcuts
        self.triggerCropperShortcut = triggerCropperShortcut
        self.toggleRecordingShortcut = toggleRecordingShortcut
        self.audioOnlyRecordingShortcut = audioOnlyRecordingShortcut
        self.quickRecordLastShortcut = quickRecordLastShortcut
        self.updatePreferences = updatePreferences
        self.showTimeInMenuBar = showTimeInMenuBar
        self.exportPresets = exportPresets
        self.quickExportPresetID = quickExportPresetID
        self.rememberLastCapture = rememberLastCapture
        self.lastCaptureMemory = lastCaptureMemory
    }

    private enum CodingKeys: String, CodingKey {
        case recordingsDirectory
        case showCursor
        case highlightClicks
        case record60FPS
        case loopExports
        case recordAudio
        case audioInputDeviceID
        case audioInputDeviceName
        case audioOnlyFormat
        case enableShortcuts
        case triggerCropperShortcut
        case toggleRecordingShortcut
        case audioOnlyRecordingShortcut
        case quickRecordLastShortcut
        case updatePreferences
        case showTimeInMenuBar
        case exportPresets
        case quickExportPresetID
        case rememberLastCapture
        case lastCaptureMemory
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultUpdatePreferences = UpdatePreferences.defaults

        recordingsDirectory = try container.decode(URL.self, forKey: .recordingsDirectory)
        showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor)
            ?? true
        highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks)
            ?? false
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
        audioOnlyRecordingShortcut = try container.decodeIfPresent(String.self, forKey: .audioOnlyRecordingShortcut)
            ?? ""
        quickRecordLastShortcut = try container.decodeIfPresent(String.self, forKey: .quickRecordLastShortcut)
            ?? ""
        updatePreferences = try container.decodeIfPresent(UpdatePreferences.self, forKey: .updatePreferences)
            ?? defaultUpdatePreferences
        showTimeInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showTimeInMenuBar)
            ?? true
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
