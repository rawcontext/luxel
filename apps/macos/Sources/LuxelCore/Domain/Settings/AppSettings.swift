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

public struct CameraPreviewPlacement: Codable, Equatable, Sendable {
    public let xPosition: Double
    public let yPosition: Double

    public init(x xPosition: Double, y yPosition: Double) throws {
        guard xPosition.isFinite, yPosition.isFinite else {
            throw AppSettingsError.invalidCameraPreviewPlacement
        }

        self.xPosition = xPosition
        self.yPosition = yPosition
    }

    fileprivate enum CodingKeys: String, CodingKey {
        case xPosition = "x"
        case yPosition = "y"
    }
}

public enum AppSettingsError: Error, Equatable {
    case invalidCameraPreviewPlacement
    case invalidRecordingFrameRate
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
    public var keystrokeOverlayEnabled: Bool
    public var keystrokeRenderOptions: KeystrokeRenderOptions
    public var pauseKeystrokeCaptureShortcut: String
    public var record60FPS: Bool
    public var recordingFrameRate: FrameRate
    public var loopExports: Bool
    public var recordSystemAudio: Bool
    public var recordAudio: Bool
    public var audioInputDeviceID: String?
    public var audioInputDeviceName: String?
    public var audioOnlyFormat: AudioRecordingFormat
    public var transcriptTurnSegmentationEnabled: Bool
    public var cameraDeviceID: String?
    public var cameraSeparateTrack: Bool
    public var cameraPreviewStyle: CameraPreviewStyle
    public var cameraPreviewPlacements: [DisplayID: CameraPreviewPlacement]
    public var replayBufferConfiguration: ReplayBufferConfiguration?
    public var replayBufferPreferredBufferLength: TimeInterval
    public var replayBufferResumeOnLaunch: Bool
    public var replayBufferConsentAccepted: Bool
    public var replayClipDestination: ReplayClipDestination
    public var notchSurfaceSettings: NotchSurfaceSettings {
        didSet {
            if !notchSurfaceSettings.isEnabled {
                hideMenuBarIcon = false
            }
        }
    }
    public var enableShortcuts: Bool
    public var triggerCropperShortcut: String
    public var toggleRecordingShortcut: String
    public var recordActiveWindowShortcut: String
    public var recordFullscreenShortcut: String
    public var audioOnlyRecordingShortcut: String
    public var quickRecordLastShortcut: String
    public var clipReplayBufferShortcut: String
    public var updatePreferences: UpdatePreferences
    public var showTimeInMenuBar: Bool
    public var hideMenuBarIcon: Bool
    public var launchAtLogin: Bool
    public var commandLineToolInstall: CommandLineToolInstall?
    public var commandLineShell: CommandLineShell
    public var notificationReminder: Bool
    public var allowURLAutomation: Bool
    public var urlAutomationGrants: [String]
    public var exportPresets: [ExportPreset]
    public var quickExportPresetID: UUID?
    public var rememberLastCapture: Bool
    public var loupeAlwaysOn: Bool
    public var dimOtherDisplays: Bool
    public var restoreLastSelection: Bool
    public var userSizePresets: [CaptureSizePreset]
    public var lastCaptureMemory: LastCaptureMemory?
    public var perFormatExportMemory: [ExportFormat: ExportMemory]
    public var lastSelectedExportFormat: ExportFormat?
    public var confirmDiscard: Bool
    public var defaultCountdown: TimeInterval?
    public var lastStopAfter: TimeInterval?
}

extension AppSettings {
    public var cameraRecordingOptions: CameraRecordingOptions? {
        guard let cameraDeviceID else {
            return nil
        }

        return CameraRecordingOptions(
            deviceID: cameraDeviceID,
            isEnabled: true,
            recordsSeparateTrack: cameraSeparateTrack,
            previewStyle: cameraPreviewStyle
        )
    }

    public var notchSurfacePreferences: NotchSurfacePreferences {
        notchSurfaceSettings.surfacePreferences
    }

    public init(
        recordingsDirectory: URL,
        recordingsDirectoryBookmark: BookmarkedDirectory? = nil,
        showCursor: Bool = true,
        highlightClicks: Bool = false,
        cursorMode: CursorMode? = nil,
        cursorRenderOptions: CursorRenderOptions? = nil,
        keystrokeOverlayEnabled: Bool = false,
        keystrokeRenderOptions: KeystrokeRenderOptions = .standard,
        pauseKeystrokeCaptureShortcut: String = "",
        record60FPS: Bool = true,
        recordingFrameRate: FrameRate? = nil,
        loopExports: Bool = true,
        recordSystemAudio: Bool = true,
        recordAudio: Bool = false,
        audioInputDeviceID: String? = AudioInputDeviceID.systemDefault,
        audioInputDeviceName: String? = AudioInputDeviceOption.systemDefault.name,
        audioOnlyFormat: AudioRecordingFormat = .aac,
        transcriptTurnSegmentationEnabled: Bool = false,
        cameraDeviceID: String? = nil,
        cameraSeparateTrack: Bool = true,
        cameraPreviewStyle: CameraPreviewStyle = CameraPreviewStyle(),
        cameraPreviewPlacements: [DisplayID: CameraPreviewPlacement] = [:],
        replayBufferConfiguration: ReplayBufferConfiguration? = nil,
        replayBufferPreferredBufferLength: TimeInterval? = nil,
        replayBufferResumeOnLaunch: Bool = false,
        replayBufferConsentAccepted: Bool = false,
        replayClipDestination: ReplayClipDestination = .editor,
        notchSurfaceSettings: NotchSurfaceSettings = .defaults,
        enableShortcuts: Bool = true,
        triggerCropperShortcut: String = "",
        toggleRecordingShortcut: String = "",
        recordActiveWindowShortcut: String = "",
        recordFullscreenShortcut: String = "",
        audioOnlyRecordingShortcut: String = "",
        quickRecordLastShortcut: String = "",
        clipReplayBufferShortcut: String = "",
        updatePreferences: UpdatePreferences = .defaults,
        showTimeInMenuBar: Bool = true,
        hideMenuBarIcon: Bool = false,
        launchAtLogin: Bool = true,
        commandLineToolInstall: CommandLineToolInstall? = nil,
        commandLineShell: CommandLineShell = .zsh,
        notificationReminder: Bool = true,
        allowURLAutomation: Bool = true,
        urlAutomationGrants: [String] = [],
        exportPresets: [ExportPreset] = ExportPreset.builtInDefaults,
        quickExportPresetID: UUID? = ExportPreset.quickGIFID,
        rememberLastCapture: Bool = true,
        loupeAlwaysOn: Bool = false,
        dimOtherDisplays: Bool = false,
        restoreLastSelection: Bool = true,
        userSizePresets: [CaptureSizePreset] = CaptureSizePreset.builtInDefaults,
        lastCaptureMemory: LastCaptureMemory? = nil,
        perFormatExportMemory: [ExportFormat: ExportMemory] = [:],
        lastSelectedExportFormat: ExportFormat? = nil,
        confirmDiscard: Bool = true,
        defaultCountdown: TimeInterval? = nil,
        lastStopAfter: TimeInterval? = nil
    ) {
        self.recordingsDirectory = recordingsDirectory
        self.recordingsDirectoryBookmark = recordingsDirectoryBookmark
        self.showCursor = showCursor
        self.highlightClicks = highlightClicks
        self.cursorMode = cursorMode ?? Self.cursorMode(showCursor: showCursor)
        self.cursorRenderOptions =
            cursorRenderOptions
            ?? Self.cursorRenderOptions(
                showCursor: showCursor,
                highlightClicks: highlightClicks
            )
        self.keystrokeOverlayEnabled = keystrokeOverlayEnabled
        self.keystrokeRenderOptions = keystrokeRenderOptions
        self.pauseKeystrokeCaptureShortcut = pauseKeystrokeCaptureShortcut
        let resolvedRecordingFrameRate =
            Self.supportedRecordingFrameRate(
                recordingFrameRate ?? Self.legacyRecordingFrameRate(record60FPS: record60FPS)
            ) ?? Self.legacyRecordingFrameRate(record60FPS: record60FPS)
        self.record60FPS = resolvedRecordingFrameRate.framesPerSecond == 60
        self.recordingFrameRate = resolvedRecordingFrameRate
        self.loopExports = loopExports
        self.recordSystemAudio = recordSystemAudio
        self.recordAudio = recordAudio
        self.audioInputDeviceID = audioInputDeviceID
        self.audioInputDeviceName = audioInputDeviceName
        self.audioOnlyFormat = audioOnlyFormat
        self.transcriptTurnSegmentationEnabled = transcriptTurnSegmentationEnabled
        self.cameraDeviceID = cameraDeviceID.flatMap(Self.nonEmpty)
        self.cameraSeparateTrack = cameraSeparateTrack
        self.cameraPreviewStyle = cameraPreviewStyle
        self.cameraPreviewPlacements = cameraPreviewPlacements
        self.replayBufferConfiguration = replayBufferConfiguration
        self.replayBufferPreferredBufferLength =
            Self.supportedReplayBufferLength(
                replayBufferPreferredBufferLength ?? replayBufferConfiguration?.bufferLength
            ) ?? ReplayBufferConfiguration.defaults.bufferLength
        self.replayBufferResumeOnLaunch = replayBufferResumeOnLaunch
        self.replayBufferConsentAccepted = replayBufferConsentAccepted
        self.replayClipDestination = replayClipDestination
        self.notchSurfaceSettings = notchSurfaceSettings
        self.enableShortcuts = enableShortcuts
        self.triggerCropperShortcut = triggerCropperShortcut
        self.toggleRecordingShortcut = toggleRecordingShortcut
        self.recordActiveWindowShortcut = recordActiveWindowShortcut
        self.recordFullscreenShortcut = recordFullscreenShortcut
        self.audioOnlyRecordingShortcut = audioOnlyRecordingShortcut
        self.quickRecordLastShortcut = quickRecordLastShortcut
        self.clipReplayBufferShortcut = clipReplayBufferShortcut
        self.updatePreferences = updatePreferences
        self.showTimeInMenuBar = showTimeInMenuBar
        self.hideMenuBarIcon = hideMenuBarIcon && notchSurfaceSettings.isEnabled
        self.launchAtLogin = launchAtLogin
        self.commandLineToolInstall = commandLineToolInstall
        self.commandLineShell = commandLineShell
        self.notificationReminder = notificationReminder
        self.allowURLAutomation = true
        self.urlAutomationGrants = urlAutomationGrants
        self.exportPresets = exportPresets
        self.quickExportPresetID = quickExportPresetID
        self.rememberLastCapture = rememberLastCapture
        self.loupeAlwaysOn = loupeAlwaysOn
        self.dimOtherDisplays = dimOtherDisplays
        self.restoreLastSelection = restoreLastSelection
        self.userSizePresets = Self.removingRemovedBuiltInSizePresets(from: userSizePresets)
        self.lastCaptureMemory = lastCaptureMemory
        self.perFormatExportMemory = perFormatExportMemory
        self.lastSelectedExportFormat = lastSelectedExportFormat
        self.confirmDiscard = confirmDiscard
        self.defaultCountdown = defaultCountdown
        self.lastStopAfter = lastStopAfter
    }

    static func removingRemovedBuiltInSizePresets(
        from presets: [CaptureSizePreset]
    ) -> [CaptureSizePreset] {
        presets.filter { !CaptureSizePreset.removedBuiltInDefaultIDs.contains($0.id) }
    }

    static func supportedReplayBufferLength(_ bufferLength: TimeInterval?) -> TimeInterval? {
        guard let bufferLength,
              bufferLength.isFinite,
              (10...600).contains(bufferLength)
        else {
            return nil
        }

        return bufferLength
    }
}
