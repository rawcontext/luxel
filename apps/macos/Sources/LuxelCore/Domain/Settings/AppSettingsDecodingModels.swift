import Foundation

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case recordingsDirectory
        case recordingsDirectoryBookmark
        case showCursor
        case highlightClicks
        case cursorMode
        case cursorRenderOptions
        case keystrokeOverlayEnabled
        case keystrokeLivePreviewEnabled
        case keystrokeRenderOptions
        case pauseKeystrokeCaptureShortcut
        case record60FPS
        case recordingFrameRate
        case matchDisplayFrameRate
        case loopExports
        case recordSystemAudio
        case recordAudio
        case audioInputDeviceID
        case audioInputDeviceName
        case audioOnlyFormat
        case speechDetectionPromptsEnabled
        case speechDetectionDisclosureAccepted
        case transcriptTurnSegmentationEnabled
        case transcriptSpeakerDiarizationEnabled
        case automaticRecordingTitles
        case transcriptLanguageIdentifier
        case cameraDeviceID
        case cameraSeparateTrack
        case cameraPreviewStyle
        case cameraPreviewPlacements
        case replayBufferConfiguration
        case replayBufferPreferredBufferLength
        case replayBufferResumeOnLaunch
        case replayBufferConsentAccepted
        case alwaysShowReplayBufferIsland
        case replayClipDestination
        case notchSurfaceSettings
        case enableShortcuts
        case triggerCropperShortcut
        case toggleRecordingShortcut
        case recordActiveWindowShortcut
        case recordFullscreenShortcut
        case audioOnlyRecordingShortcut
        case quickRecordLastShortcut
        case clipReplayBufferShortcut
        case updatePreferences
        case showTimeInMenuBar
        case hideMenuBarIcon
        case launchAtLogin
        case commandLineControlEnabled
        case commandLinePairedClients
        case commandLineFolderGrants
        case notificationReminder
        case exportCompletionNotificationsEnabled
        case allowURLAutomation
        case urlAutomationGrants
        case exportPresets
        case quickExportPresetID
        case rememberLastCapture
        case loupeAlwaysOn
        case dimOtherDisplays
        case restoreLastSelection
        case userSizePresets
        case lastCaptureMemory
        case perFormatExportMemory
        case lastSelectedExportFormat
        case confirmDiscard
        case defaultCountdown
        case lastStopAfter
    }
}

typealias AppSettingsDecoder = KeyedDecodingContainer<AppSettings.CodingKeys>

struct CursorSettings {
    let showCursor: Bool
    let highlightClicks: Bool
    let mode: CursorMode
    let renderOptions: CursorRenderOptions
    let keystrokeOverlayEnabled: Bool
    let keystrokeLivePreviewEnabled: Bool
    let keystrokeRenderOptions: KeystrokeRenderOptions
    let pauseKeystrokeCaptureShortcut: String
}

struct RecordingSettings {
    let frameRate: FrameRate
    let records60FPS: Bool
    let matchesDisplayFrameRate: Bool
    let loopsExports: Bool
    let recordsSystemAudio: Bool
    let recordsAudio: Bool
    let audioOnlyFormat: AudioRecordingFormat

    init(
        frameRate: FrameRate,
        matchesDisplayFrameRate: Bool,
        loopsExports: Bool,
        recordsSystemAudio: Bool,
        recordsAudio: Bool,
        audioOnlyFormat: AudioRecordingFormat
    ) {
        self.frameRate = frameRate
        records60FPS = frameRate.framesPerSecond == 60
        self.matchesDisplayFrameRate = matchesDisplayFrameRate
        self.loopsExports = loopsExports
        self.recordsSystemAudio = recordsSystemAudio
        self.recordsAudio = recordsAudio
        self.audioOnlyFormat = audioOnlyFormat
    }
}

struct AudioInputSettings {
    let id: String?
    let name: String?
}

struct TranscriptSettings {
    let turnSegmentationEnabled: Bool
    let speakerDiarizationEnabled: Bool
    let languageIdentifier: String?
}

struct CaptureSurfaceSettings {
    let cameraDeviceID: String?
    let cameraSeparateTrack: Bool
    let cameraPreviewStyle: CameraPreviewStyle
    let cameraPreviewPlacements: [DisplayID: CameraPreviewPlacement]
    let replayBufferConfiguration: ReplayBufferConfiguration?
    let replayBufferPreferredBufferLength: TimeInterval
    let replayBufferResumeOnLaunch: Bool
    let replayBufferConsentAccepted: Bool
    let alwaysShowReplayBufferIsland: Bool
    let replayClipDestination: ReplayClipDestination
    let notchSurfaceSettings: NotchSurfaceSettings
    let enableShortcuts: Bool
}

struct ShortcutSettings {
    let triggerCropper: String
    let toggleRecording: String
    let recordActiveWindow: String
    let recordFullscreen: String
    let audioOnlyRecording: String
    let quickRecordLast: String
    let clipReplayBuffer: String
}

struct GeneralSettings {
    let updatePreferences: UpdatePreferences
    let showTimeInMenuBar: Bool
    let hideMenuBarIcon: Bool
    let launchAtLogin: Bool
    let commandLineControlEnabled: Bool
    let commandLinePairedClients: [CommandLinePairedClient]
    let commandLineFolderGrants: [CommandLineFolderGrant]
    let notificationReminder: Bool
    let exportCompletionNotificationsEnabled: Bool
    let urlAutomationGrants: [String]
    let exportPresets: [ExportPreset]
    let quickExportPresetID: UUID?
    let rememberLastCapture: Bool
    let loupeAlwaysOn: Bool
    let dimOtherDisplays: Bool
    let restoreLastSelection: Bool
    let userSizePresets: [CaptureSizePreset]
    let lastCaptureMemory: LastCaptureMemory?
    let perFormatExportMemory: [ExportFormat: ExportMemory]
    let lastSelectedExportFormat: ExportFormat?
    let confirmDiscard: Bool
    let defaultCountdown: TimeInterval?
    let lastStopAfter: TimeInterval?
}
