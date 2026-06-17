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
        case keystrokeRenderOptions
        case pauseKeystrokeCaptureShortcut
        case record60FPS
        case recordingFrameRate
        case loopExports
        case recordSystemAudio
        case recordAudio
        case audioInputDeviceID
        case audioInputDeviceName
        case audioOnlyFormat
        case cameraDeviceID
        case cameraSeparateTrack
        case cameraPreviewStyle
        case cameraPreviewPlacements
        case replayBufferConfiguration
        case replayBufferResumeOnLaunch
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
        case loupeAlwaysOn
        case dimOtherDisplays
        case restoreLastSelection
        case userSizePresets
        case lastCaptureMemory
        case perFormatExportMemory
        case screenshotFormat
        case screenshotDestinations
        case screenshotShowThumbnail
        case screenshotBackdrop
        case confirmDiscard
        case defaultCountdown
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
        keystrokeOverlayEnabled = try container.decodeIfPresent(Bool.self, forKey: .keystrokeOverlayEnabled)
            ?? false
        keystrokeRenderOptions = try container.decodeIfPresent(
            KeystrokeRenderOptions.self,
            forKey: .keystrokeRenderOptions
        ) ?? .standard
        pauseKeystrokeCaptureShortcut = try container.decodeIfPresent(
            String.self,
            forKey: .pauseKeystrokeCaptureShortcut
        ) ?? ""
        let recording = try Self.decodeRecordingSettings(from: container)
        recordingFrameRate = recording.frameRate
        record60FPS = recording.records60FPS
        loopExports = recording.loopsExports
        recordSystemAudio = recording.recordsSystemAudio
        recordAudio = recording.recordsAudio
        let audioInput = try Self.decodeAudioInput(from: container)
        audioInputDeviceID = audioInput.id
        audioInputDeviceName = audioInput.name
        audioOnlyFormat = recording.audioOnlyFormat
        let capture = try Self.decodeCaptureSurfaceSettings(from: container)
        cameraDeviceID = capture.cameraDeviceID
        cameraSeparateTrack = capture.cameraSeparateTrack
        cameraPreviewStyle = capture.cameraPreviewStyle
        cameraPreviewPlacements = capture.cameraPreviewPlacements
        replayBufferConfiguration = capture.replayBufferConfiguration
        replayBufferResumeOnLaunch = capture.replayBufferResumeOnLaunch
        replayClipDestination = capture.replayClipDestination
        notchSurfaceSettings = capture.notchSurfaceSettings
        enableShortcuts = capture.enableShortcuts
        let shortcuts = try Self.decodeShortcuts(from: container)
        triggerCropperShortcut = shortcuts.triggerCropper
        toggleRecordingShortcut = shortcuts.toggleRecording
        recordActiveWindowShortcut = shortcuts.recordActiveWindow
        recordFullscreenShortcut = shortcuts.recordFullscreen
        audioOnlyRecordingShortcut = shortcuts.audioOnlyRecording
        quickRecordLastShortcut = shortcuts.quickRecordLast
        clipReplayBufferShortcut = shortcuts.clipReplayBuffer
        captureScreenshotShortcut = shortcuts.captureScreenshot
        screenshotActiveWindowShortcut = shortcuts.screenshotActiveWindow
        screenshotFullscreenShortcut = shortcuts.screenshotFullscreen
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
        loupeAlwaysOn = try container.decodeIfPresent(Bool.self, forKey: .loupeAlwaysOn)
            ?? false
        dimOtherDisplays = try container.decodeIfPresent(Bool.self, forKey: .dimOtherDisplays)
            ?? false
        restoreLastSelection = try container.decodeIfPresent(Bool.self, forKey: .restoreLastSelection)
            ?? true
        userSizePresets = Self.removingRemovedBuiltInSizePresets(
            from: try container.decodeIfPresent([CaptureSizePreset].self, forKey: .userSizePresets)
                ?? CaptureSizePreset.builtInDefaults
        )
        lastCaptureMemory = try container.decodeIfPresent(LastCaptureMemory.self, forKey: .lastCaptureMemory)
        perFormatExportMemory = try container.decodeIfPresent(
            [ExportFormat: ExportMemory].self,
            forKey: .perFormatExportMemory
        ) ?? [:]
        let screenshot = try Self.decodeScreenshotSettings(from: container)
        screenshotFormat = screenshot.format
        screenshotDestinations = screenshot.destinations
        screenshotShowThumbnail = screenshot.showsThumbnail
        screenshotBackdrop = screenshot.backdrop
        confirmDiscard = try container.decodeIfPresent(Bool.self, forKey: .confirmDiscard)
            ?? true
        defaultCountdown = try container.decodeIfPresent(TimeInterval.self, forKey: .defaultCountdown)
        lastStopAfter = try container.decodeIfPresent(TimeInterval.self, forKey: .lastStopAfter)
    }

    private static func decodeRecordingSettings(from container: AppSettingsDecoder) throws -> RecordingSettings {
        let legacyRecord60FPS = try container.decodeIfPresent(Bool.self, forKey: .record60FPS)
            ?? true
        let frameRate = Self.supportedRecordingFrameRate(
            try container.decodeIfPresent(FrameRate.self, forKey: .recordingFrameRate)
        ) ?? Self.legacyRecordingFrameRate(record60FPS: legacyRecord60FPS)

        return try RecordingSettings(
            frameRate: frameRate,
            loopsExports: container.decodeIfPresent(Bool.self, forKey: .loopExports) ?? true,
            recordsSystemAudio: container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio)
                ?? (container.decodeIfPresent(Bool.self, forKey: .recordAudio) ?? false),
            recordsAudio: container.decodeIfPresent(Bool.self, forKey: .recordAudio) ?? false,
            audioOnlyFormat: container.decodeIfPresent(AudioRecordingFormat.self, forKey: .audioOnlyFormat) ?? .aac
        )
    }

    private static func decodeAudioInput(from container: AppSettingsDecoder) throws -> AudioInputSettings {
        let id: String?
        if container.contains(.audioInputDeviceID) {
            id = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceID)
        } else {
            id = AudioInputDeviceID.systemDefault
        }

        let name: String?
        if container.contains(.audioInputDeviceName) {
            name = try container.decodeIfPresent(String.self, forKey: .audioInputDeviceName)
        } else if id == AudioInputDeviceID.systemDefault {
            name = AudioInputDeviceOption.systemDefault.name
        } else {
            name = nil
        }

        return AudioInputSettings(id: id, name: name)
    }

    private static func decodeCaptureSurfaceSettings(
        from container: AppSettingsDecoder
    ) throws -> CaptureSurfaceSettings {
        try CaptureSurfaceSettings(
            cameraDeviceID: container.decodeIfPresent(String.self, forKey: .cameraDeviceID).flatMap(Self.nonEmpty),
            cameraSeparateTrack: container.decodeIfPresent(Bool.self, forKey: .cameraSeparateTrack) ?? true,
            cameraPreviewStyle: container.decodeIfPresent(CameraPreviewStyle.self, forKey: .cameraPreviewStyle)
                ?? CameraPreviewStyle(),
            cameraPreviewPlacements: container.decodeIfPresent(
                [DisplayID: CameraPreviewPlacement].self,
                forKey: .cameraPreviewPlacements
            ) ?? [:],
            replayBufferConfiguration: container.decodeIfPresent(
                ReplayBufferConfiguration.self,
                forKey: .replayBufferConfiguration
            ),
            replayBufferResumeOnLaunch: container.decodeIfPresent(
                Bool.self,
                forKey: .replayBufferResumeOnLaunch
            ) ?? false,
            replayClipDestination: container.decodeIfPresent(ReplayClipDestination.self, forKey: .replayClipDestination)
                ?? .editor,
            notchSurfaceSettings: container.decodeIfPresent(NotchSurfaceSettings.self, forKey: .notchSurfaceSettings)
                ?? .defaults,
            enableShortcuts: container.decodeIfPresent(Bool.self, forKey: .enableShortcuts) ?? true
        )
    }

    private static func decodeShortcuts(from container: AppSettingsDecoder) throws -> ShortcutSettings {
        try ShortcutSettings(
            triggerCropper: container.decodeIfPresent(String.self, forKey: .triggerCropperShortcut) ?? "",
            toggleRecording: container.decodeIfPresent(String.self, forKey: .toggleRecordingShortcut) ?? "",
            recordActiveWindow: container.decodeIfPresent(String.self, forKey: .recordActiveWindowShortcut) ?? "",
            recordFullscreen: container.decodeIfPresent(String.self, forKey: .recordFullscreenShortcut) ?? "",
            audioOnlyRecording: container.decodeIfPresent(String.self, forKey: .audioOnlyRecordingShortcut) ?? "",
            quickRecordLast: container.decodeIfPresent(String.self, forKey: .quickRecordLastShortcut) ?? "",
            clipReplayBuffer: container.decodeIfPresent(String.self, forKey: .clipReplayBufferShortcut) ?? "",
            captureScreenshot: container.decodeIfPresent(String.self, forKey: .captureScreenshotShortcut) ?? "",
            screenshotActiveWindow: container.decodeIfPresent(
                String.self,
                forKey: .screenshotActiveWindowShortcut
            ) ?? "",
            screenshotFullscreen: container.decodeIfPresent(String.self, forKey: .screenshotFullscreenShortcut) ?? ""
        )
    }

    private static func decodeScreenshotSettings(from container: AppSettingsDecoder) throws -> ScreenshotSettings {
        try ScreenshotSettings(
            format: container.decodeIfPresent(ScreenshotFormat.self, forKey: .screenshotFormat) ?? .png,
            destinations: container.decodeIfPresent([ScreenshotDestination].self, forKey: .screenshotDestinations)
                ?? [.clipboard, .file],
            showsThumbnail: container.decodeIfPresent(Bool.self, forKey: .screenshotShowThumbnail) ?? true,
            backdrop: container.decodeIfPresent(CaptureBackdrop.self, forKey: .screenshotBackdrop) ?? .opaque
        )
    }

    static func cursorMode(showCursor: Bool) -> CursorMode {
        showCursor ? .baked : .hidden
    }

    static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    public mutating func setRecordingFrameRate(_ framesPerSecond: Int) throws {
        let frameRate = try Self.makeRecordingFrameRate(framesPerSecond)
        recordingFrameRate = frameRate
        record60FPS = frameRate.framesPerSecond == 60
    }

    public static func makeRecordingFrameRate(_ framesPerSecond: Int) throws -> FrameRate {
        guard (1...60).contains(framesPerSecond) else {
            throw AppSettingsError.invalidRecordingFrameRate
        }

        return try FrameRate(framesPerSecond)
    }

    static func supportedRecordingFrameRate(_ frameRate: FrameRate?) -> FrameRate? {
        guard let frameRate,
              (1...60).contains(frameRate.framesPerSecond) else {
            return nil
        }

        return frameRate
    }

    static func legacyRecordingFrameRate(record60FPS: Bool) -> FrameRate {
        record60FPS ? .fps60 : .fps30
    }

    static func cursorRenderOptions(
        showCursor: Bool,
        highlightClicks: Bool
    ) -> CursorRenderOptions {
        CursorRenderOptions.standard(
            isVisible: showCursor,
            clickStyle: highlightClicks ? .ringRipple : .none
        )
    }
}

private typealias AppSettingsDecoder = KeyedDecodingContainer<AppSettings.CodingKeys>

private struct RecordingSettings {
    let frameRate: FrameRate
    let records60FPS: Bool
    let loopsExports: Bool
    let recordsSystemAudio: Bool
    let recordsAudio: Bool
    let audioOnlyFormat: AudioRecordingFormat

    init(
        frameRate: FrameRate,
        loopsExports: Bool,
        recordsSystemAudio: Bool,
        recordsAudio: Bool,
        audioOnlyFormat: AudioRecordingFormat
    ) {
        self.frameRate = frameRate
        records60FPS = frameRate.framesPerSecond == 60
        self.loopsExports = loopsExports
        self.recordsSystemAudio = recordsSystemAudio
        self.recordsAudio = recordsAudio
        self.audioOnlyFormat = audioOnlyFormat
    }
}

private struct AudioInputSettings {
    let id: String?
    let name: String?
}

private struct CaptureSurfaceSettings {
    let cameraDeviceID: String?
    let cameraSeparateTrack: Bool
    let cameraPreviewStyle: CameraPreviewStyle
    let cameraPreviewPlacements: [DisplayID: CameraPreviewPlacement]
    let replayBufferConfiguration: ReplayBufferConfiguration?
    let replayBufferResumeOnLaunch: Bool
    let replayClipDestination: ReplayClipDestination
    let notchSurfaceSettings: NotchSurfaceSettings
    let enableShortcuts: Bool
}

private struct ShortcutSettings {
    let triggerCropper: String
    let toggleRecording: String
    let recordActiveWindow: String
    let recordFullscreen: String
    let audioOnlyRecording: String
    let quickRecordLast: String
    let clipReplayBuffer: String
    let captureScreenshot: String
    let screenshotActiveWindow: String
    let screenshotFullscreen: String
}

private struct ScreenshotSettings {
    let format: ScreenshotFormat
    let destinations: [ScreenshotDestination]
    let showsThumbnail: Bool
    let backdrop: CaptureBackdrop
}
