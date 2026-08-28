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
    public static let recordingFrameRateRange = 1...120

    public static var defaultRecordingsDirectory: URL {
        let moviesDirectory =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

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
    public var keystrokeLivePreviewEnabled: Bool
    public var keystrokeRenderOptions: KeystrokeRenderOptions
    public var pauseKeystrokeCaptureShortcut: String
    public var record60FPS: Bool
    public var recordingFrameRate: FrameRate
    public var matchDisplayFrameRate: Bool
    public var loopExports: Bool
    public var recordSystemAudio: Bool
    public var recordAudio: Bool
    public var audioInputDeviceID: String?
    public var audioInputDeviceName: String?
    public var audioOnlyFormat: AudioRecordingFormat
    public var speechDetectionPromptsEnabled: Bool
    public var speechDetectionDisclosureAccepted: Bool
    public var transcriptTurnSegmentationEnabled: Bool
    public var transcriptSpeakerDiarizationEnabled: Bool
    public var transcriptLanguageIdentifier: String?
    public var cameraDeviceID: String?
    public var cameraSeparateTrack: Bool
    public var cameraPreviewStyle: CameraPreviewStyle
    public var cameraPreviewPlacements: [DisplayID: CameraPreviewPlacement]
    public var replayBufferConfiguration: ReplayBufferConfiguration?
    public var replayBufferPreferredBufferLength: TimeInterval
    public var replayBufferResumeOnLaunch: Bool
    public var replayBufferConsentAccepted: Bool
    public var alwaysShowReplayBufferIsland: Bool
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
    public var commandLineControlEnabled: Bool
    public var commandLinePairedClients: [CommandLinePairedClient]
    public var commandLineFolderGrants: [CommandLineFolderGrant]
    public var notificationReminder: Bool
    public var exportCompletionNotificationsEnabled: Bool
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
        keystrokeOverlayEnabled overlayEnabled: Bool = false,
        keystrokeLivePreviewEnabled livePreviewEnabled: Bool = true,
        keystrokeRenderOptions keystrokeOptions: KeystrokeRenderOptions = .standard,
        pauseKeystrokeCaptureShortcut pauseShortcut: String = "",
        record60FPS: Bool = true,
        recordingFrameRate: FrameRate? = nil,
        matchDisplayFrameRate: Bool = false,
        loopExports: Bool = true,
        recordSystemAudio: Bool = true,
        recordAudio: Bool = false,
        audioInputDeviceID audioDeviceID: String? = AudioInputDeviceID.systemDefault,
        audioInputDeviceName audioDeviceName: String? = AudioInputDeviceOption.systemDefault.name,
        audioOnlyFormat audioFormat: AudioRecordingFormat = .aac,
        speechDetectionPromptsEnabled speechPromptsEnabled: Bool = false,
        speechDetectionDisclosureAccepted speechDisclosureAccepted: Bool = false,
        transcriptTurnSegmentationEnabled turnsEnabled: Bool = false,
        transcriptSpeakerDiarizationEnabled speakerDiarizationEnabled: Bool = true,
        transcriptLanguageIdentifier languageIdentifier: String? = nil,
        cameraDeviceID selectedCameraID: String? = nil,
        cameraSeparateTrack separateTrack: Bool = true,
        cameraPreviewStyle previewStyle: CameraPreviewStyle = CameraPreviewStyle(),
        cameraPreviewPlacements previewPlacements: [DisplayID: CameraPreviewPlacement] = [:],
        replayBufferConfiguration replayConfiguration: ReplayBufferConfiguration? = nil,
        replayBufferPreferredBufferLength preferredBufferLength: TimeInterval? = nil,
        replayBufferResumeOnLaunch resumeReplay: Bool = false,
        replayBufferConsentAccepted replayConsent: Bool = false,
        alwaysShowReplayBufferIsland alwaysShowReplayIsland: Bool = false,
        replayClipDestination clipDestination: ReplayClipDestination = .editor,
        notchSurfaceSettings: NotchSurfaceSettings = .defaults,
        enableShortcuts: Bool = true,
        triggerCropperShortcut cropperShortcut: String = "",
        toggleRecordingShortcut toggleShortcut: String = "",
        recordActiveWindowShortcut activeWindowShortcut: String = "",
        recordFullscreenShortcut fullscreenShortcut: String = "",
        audioOnlyRecordingShortcut audioShortcut: String = "",
        quickRecordLastShortcut quickLastShortcut: String = "",
        clipReplayBufferShortcut clipShortcut: String = "",
        updatePreferences updates: UpdatePreferences = .defaults,
        showTimeInMenuBar showTime: Bool = true,
        hideMenuBarIcon hideMenuIcon: Bool = false,
        launchAtLogin launchOnLogin: Bool = false,
        commandLineControlEnabled commandLineEnabled: Bool = false,
        commandLinePairedClients pairedClients: [CommandLinePairedClient] = [],
        commandLineFolderGrants folderGrants: [CommandLineFolderGrant] = [],
        notificationReminder showReminder: Bool = true,
        exportCompletionNotificationsEnabled exportNotifications: Bool = true,
        allowURLAutomation: Bool = true,
        urlAutomationGrants: [String] = [],
        exportPresets: [ExportPreset] = ExportPreset.builtInDefaults,
        quickExportPresetID: UUID? = ExportPreset.quickGIFID,
        rememberLastCapture: Bool = true,
        loupeAlwaysOn: Bool = false,
        dimOtherDisplays: Bool = false,
        restoreLastSelection: Bool = true,
        userSizePresets sizePresets: [CaptureSizePreset] = CaptureSizePreset.builtInDefaults,
        lastCaptureMemory captureMemory: LastCaptureMemory? = nil,
        perFormatExportMemory exportMemory: [ExportFormat: ExportMemory] = [:],
        lastSelectedExportFormat selectedExportFormat: ExportFormat? = nil,
        confirmDiscard: Bool = true,
        defaultCountdown: TimeInterval? = nil,
        lastStopAfter: TimeInterval? = nil
    ) {
        let resolvedCursorMode = cursorMode ?? Self.cursorMode(showCursor: showCursor)
        let renderOptions =
            cursorRenderOptions
            ?? Self.cursorRenderOptions(
                showCursor: showCursor, highlightClicks: highlightClicks
            )
        let frameRate = Self.resolvedRecordingFrameRate(
            record60FPS: record60FPS, recordingFrameRate: recordingFrameRate)
        let requestedBufferLength = preferredBufferLength ?? replayConfiguration?.bufferLength
        let bufferLength =
            Self.supportedReplayBufferLength(requestedBufferLength)
            ?? ReplayBufferConfiguration.defaults.bufferLength
        self.recordingsDirectory = recordingsDirectory
        self.recordingsDirectoryBookmark = recordingsDirectoryBookmark
        (self.showCursor, self.highlightClicks) = (showCursor, highlightClicks)
        (self.cursorMode, self.cursorRenderOptions) = (resolvedCursorMode, renderOptions)
        (self.keystrokeOverlayEnabled, self.keystrokeLivePreviewEnabled) = (overlayEnabled, livePreviewEnabled)
        (self.keystrokeRenderOptions, self.pauseKeystrokeCaptureShortcut) = (keystrokeOptions, pauseShortcut)
        (self.record60FPS, self.recordingFrameRate) = (frameRate.framesPerSecond == 60, frameRate)
        (self.matchDisplayFrameRate, self.loopExports) = (matchDisplayFrameRate, loopExports)
        (self.recordSystemAudio, self.recordAudio) = (recordSystemAudio, recordAudio)
        (self.audioInputDeviceID, self.audioInputDeviceName) = (audioDeviceID, audioDeviceName)
        (self.audioOnlyFormat, self.transcriptSpeakerDiarizationEnabled) = (audioFormat, speakerDiarizationEnabled)
        (self.speechDetectionPromptsEnabled, self.speechDetectionDisclosureAccepted) =
            (speechPromptsEnabled, speechDisclosureAccepted)
        (self.transcriptTurnSegmentationEnabled, self.cameraSeparateTrack) = (turnsEnabled, separateTrack)
        (self.transcriptLanguageIdentifier, self.cameraDeviceID) =
            (languageIdentifier.flatMap(Self.nonEmpty), selectedCameraID.flatMap(Self.nonEmpty))
        (self.cameraPreviewStyle, self.cameraPreviewPlacements) = (previewStyle, previewPlacements)
        (self.replayBufferConfiguration, self.replayBufferPreferredBufferLength) = (replayConfiguration, bufferLength)
        (self.replayBufferResumeOnLaunch, self.replayBufferConsentAccepted) = (resumeReplay, replayConsent)
        (self.alwaysShowReplayBufferIsland, self.replayClipDestination) = (alwaysShowReplayIsland, clipDestination)
        (self.notchSurfaceSettings, self.enableShortcuts) = (notchSurfaceSettings, enableShortcuts)
        (self.triggerCropperShortcut, self.toggleRecordingShortcut) = (cropperShortcut, toggleShortcut)
        (self.recordActiveWindowShortcut, self.recordFullscreenShortcut) = (activeWindowShortcut, fullscreenShortcut)
        (self.audioOnlyRecordingShortcut, self.quickRecordLastShortcut) = (audioShortcut, quickLastShortcut)
        (self.clipReplayBufferShortcut, self.updatePreferences) = (clipShortcut, updates)
        (self.showTimeInMenuBar, self.hideMenuBarIcon) = (showTime, hideMenuIcon && notchSurfaceSettings.isEnabled)
        (self.launchAtLogin, self.commandLineControlEnabled) = (launchOnLogin, commandLineEnabled)
        (self.commandLinePairedClients, self.commandLineFolderGrants) = (pairedClients, folderGrants)
        (self.notificationReminder, self.exportCompletionNotificationsEnabled) = (showReminder, exportNotifications)
        (self.allowURLAutomation, self.urlAutomationGrants) = (true, urlAutomationGrants)
        (self.exportPresets, self.quickExportPresetID) = (exportPresets, quickExportPresetID)
        (self.rememberLastCapture, self.loupeAlwaysOn) = (rememberLastCapture, loupeAlwaysOn)
        (self.dimOtherDisplays, self.restoreLastSelection) = (dimOtherDisplays, restoreLastSelection)
        (self.userSizePresets, self.lastCaptureMemory) =
            (Self.removingRemovedBuiltInSizePresets(from: sizePresets), captureMemory)
        (self.perFormatExportMemory, self.lastSelectedExportFormat) = (exportMemory, selectedExportFormat)
        (self.confirmDiscard, self.defaultCountdown) = (confirmDiscard, defaultCountdown)
        self.lastStopAfter = lastStopAfter
    }

    static func removingRemovedBuiltInSizePresets(
        from presets: [CaptureSizePreset]
    ) -> [CaptureSizePreset] {
        presets.filter { !CaptureSizePreset.removedBuiltInDefaultIDs.contains($0.id) }
    }

    static func resolvedRecordingFrameRate(
        record60FPS: Bool,
        recordingFrameRate: FrameRate?
    ) -> FrameRate {
        let legacyFrameRate = legacyRecordingFrameRate(record60FPS: record60FPS)
        return supportedRecordingFrameRate(recordingFrameRate ?? legacyFrameRate)
            ?? legacyFrameRate
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
