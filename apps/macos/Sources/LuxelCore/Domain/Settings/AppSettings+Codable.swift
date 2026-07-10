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
        case matchDisplayFrameRate
        case loopExports
        case recordSystemAudio
        case recordAudio
        case audioInputDeviceID
        case audioInputDeviceName
        case audioOnlyFormat
        case transcriptTurnSegmentationEnabled
        case transcriptSpeakerDiarizationEnabled
        case transcriptLanguageIdentifier
        case transcriptEnginePreference
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
        case commandLineToolInstall
        case commandLineShell
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
        case lastSelectedExportFormat
        case confirmDiscard
        case defaultCountdown
        case lastStopAfter
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        recordingsDirectory = try container.decode(URL.self, forKey: .recordingsDirectory)
        recordingsDirectoryBookmark = try container.decodeIfPresent(
            BookmarkedDirectory.self,
            forKey: .recordingsDirectoryBookmark
        )
        showCursor =
            try container.decodeIfPresent(Bool.self, forKey: .showCursor)
            ?? true
        highlightClicks =
            try container.decodeIfPresent(Bool.self, forKey: .highlightClicks)
            ?? false
        cursorMode =
            try container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)
            ?? Self.cursorMode(showCursor: showCursor)
        cursorRenderOptions =
            try container.decodeIfPresent(
                CursorRenderOptions.self,
                forKey: .cursorRenderOptions
            ) ?? Self.cursorRenderOptions(showCursor: showCursor, highlightClicks: highlightClicks)
        keystrokeOverlayEnabled =
            try container.decodeIfPresent(Bool.self, forKey: .keystrokeOverlayEnabled)
            ?? false
        keystrokeRenderOptions =
            try container.decodeIfPresent(
                KeystrokeRenderOptions.self,
                forKey: .keystrokeRenderOptions
            ) ?? .standard
        pauseKeystrokeCaptureShortcut =
            try container.decodeIfPresent(
                String.self,
                forKey: .pauseKeystrokeCaptureShortcut
            ) ?? ""
        let recording = try Self.decodeRecordingSettings(from: container)
        recordingFrameRate = recording.frameRate
        record60FPS = recording.records60FPS
        matchDisplayFrameRate = recording.matchesDisplayFrameRate
        loopExports = recording.loopsExports
        recordSystemAudio = recording.recordsSystemAudio
        recordAudio = recording.recordsAudio
        let audioInput = try Self.decodeAudioInput(from: container)
        audioInputDeviceID = audioInput.id
        audioInputDeviceName = audioInput.name
        audioOnlyFormat = recording.audioOnlyFormat
        let transcription = try Self.decodeTranscriptionSettings(from: container)
        transcriptTurnSegmentationEnabled = transcription.turnSegmentationEnabled
        transcriptSpeakerDiarizationEnabled = transcription.speakerDiarizationEnabled
        transcriptLanguageIdentifier = transcription.languageIdentifier
        transcriptEnginePreference = transcription.enginePreference
        let capture = try Self.decodeCaptureSurfaceSettings(from: container)
        cameraDeviceID = capture.cameraDeviceID
        cameraSeparateTrack = capture.cameraSeparateTrack
        cameraPreviewStyle = capture.cameraPreviewStyle
        cameraPreviewPlacements = capture.cameraPreviewPlacements
        replayBufferConfiguration = capture.replayBufferConfiguration
        replayBufferPreferredBufferLength = capture.replayBufferPreferredBufferLength
        replayBufferResumeOnLaunch = capture.replayBufferResumeOnLaunch
        replayBufferConsentAccepted = capture.replayBufferConsentAccepted
        alwaysShowReplayBufferIsland = capture.alwaysShowReplayBufferIsland
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
        let general = try Self.decodeGeneralSettings(from: container)
        updatePreferences = general.updatePreferences
        showTimeInMenuBar = general.showTimeInMenuBar
        hideMenuBarIcon = general.hideMenuBarIcon && notchSurfaceSettings.isEnabled
        launchAtLogin = general.launchAtLogin
        commandLineToolInstall = general.commandLineToolInstall
        commandLineShell = general.commandLineShell
        notificationReminder = general.notificationReminder
        allowURLAutomation = true
        urlAutomationGrants = general.urlAutomationGrants
        exportPresets = general.exportPresets
        quickExportPresetID = general.quickExportPresetID
        rememberLastCapture = general.rememberLastCapture
        loupeAlwaysOn = general.loupeAlwaysOn
        dimOtherDisplays = general.dimOtherDisplays
        restoreLastSelection = general.restoreLastSelection
        userSizePresets = general.userSizePresets
        lastCaptureMemory = general.lastCaptureMemory
        perFormatExportMemory = general.perFormatExportMemory
        lastSelectedExportFormat = general.lastSelectedExportFormat
        confirmDiscard = general.confirmDiscard
        defaultCountdown = general.defaultCountdown
        lastStopAfter = general.lastStopAfter
    }

    private static func decodeRecordingSettings(from container: AppSettingsDecoder) throws
    -> RecordingSettings {
        let legacyRecord60FPS =
            try container.decodeIfPresent(Bool.self, forKey: .record60FPS)
            ?? true
        let frameRate =
            Self.supportedRecordingFrameRate(
                try container.decodeIfPresent(FrameRate.self, forKey: .recordingFrameRate)
            ) ?? Self.legacyRecordingFrameRate(record60FPS: legacyRecord60FPS)

        return try RecordingSettings(
            frameRate: frameRate,
            matchesDisplayFrameRate: container.decodeIfPresent(
                Bool.self, forKey: .matchDisplayFrameRate) ?? false,
            loopsExports: container.decodeIfPresent(Bool.self, forKey: .loopExports) ?? true,
            recordsSystemAudio: container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio)
                ?? (container.decodeIfPresent(Bool.self, forKey: .recordAudio) ?? false),
            recordsAudio: container.decodeIfPresent(Bool.self, forKey: .recordAudio) ?? false,
            audioOnlyFormat: container.decodeIfPresent(
                AudioRecordingFormat.self, forKey: .audioOnlyFormat) ?? .aac
        )
    }

    private static func decodeTranscriptionSettings(
        from container: AppSettingsDecoder
    ) throws -> TranscriptSettings {
        try TranscriptSettings(
            turnSegmentationEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .transcriptTurnSegmentationEnabled
            ) ?? false,
            speakerDiarizationEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .transcriptSpeakerDiarizationEnabled
            ) ?? true,
            languageIdentifier: container.decodeIfPresent(
                String.self,
                forKey: .transcriptLanguageIdentifier
            ).flatMap(Self.nonEmpty),
            enginePreference: container.decodeIfPresent(
                TranscriptEnginePreference.self,
                forKey: .transcriptEnginePreference
            ) ?? .appleSpeech
        )
    }

    private static func decodeAudioInput(from container: AppSettingsDecoder) throws
    -> AudioInputSettings {
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
        let replayBufferConfiguration = try container.decodeIfPresent(
            ReplayBufferConfiguration.self,
            forKey: .replayBufferConfiguration
        )
        let replayBufferPreferredBufferLength =
            Self.supportedReplayBufferLength(
                try container.decodeIfPresent(
                    TimeInterval.self,
                    forKey: .replayBufferPreferredBufferLength
                ) ?? replayBufferConfiguration?.bufferLength
            ) ?? ReplayBufferConfiguration.defaults.bufferLength

        return try CaptureSurfaceSettings(
            cameraDeviceID: container.decodeIfPresent(String.self, forKey: .cameraDeviceID).flatMap(
                Self.nonEmpty),
            cameraSeparateTrack: container.decodeIfPresent(Bool.self, forKey: .cameraSeparateTrack)
                ?? true,
            cameraPreviewStyle: container.decodeIfPresent(
                CameraPreviewStyle.self, forKey: .cameraPreviewStyle)
                ?? CameraPreviewStyle(),
            cameraPreviewPlacements: container.decodeIfPresent(
                [DisplayID: CameraPreviewPlacement].self,
                forKey: .cameraPreviewPlacements
            ) ?? [:],
            replayBufferConfiguration: replayBufferConfiguration,
            replayBufferPreferredBufferLength: replayBufferPreferredBufferLength,
            replayBufferResumeOnLaunch: container.decodeIfPresent(
                Bool.self,
                forKey: .replayBufferResumeOnLaunch
            ) ?? false,
            replayBufferConsentAccepted: container.decodeIfPresent(
                Bool.self,
                forKey: .replayBufferConsentAccepted
            ) ?? false,
            alwaysShowReplayBufferIsland: container.decodeIfPresent(
                Bool.self,
                forKey: .alwaysShowReplayBufferIsland
            ) ?? false,
            replayClipDestination: container.decodeIfPresent(
                ReplayClipDestination.self, forKey: .replayClipDestination)
                ?? .editor,
            notchSurfaceSettings: container.decodeIfPresent(
                NotchSurfaceSettings.self, forKey: .notchSurfaceSettings)
                ?? .defaults,
            enableShortcuts: container.decodeIfPresent(Bool.self, forKey: .enableShortcuts) ?? true
        )
    }

    private static func decodeShortcuts(from container: AppSettingsDecoder) throws -> ShortcutSettings {
        try ShortcutSettings(
            triggerCropper: container.decodeIfPresent(String.self, forKey: .triggerCropperShortcut) ?? "",
            toggleRecording: container.decodeIfPresent(String.self, forKey: .toggleRecordingShortcut)
                ?? "",
            recordActiveWindow: container.decodeIfPresent(
                String.self, forKey: .recordActiveWindowShortcut) ?? "",
            recordFullscreen: container.decodeIfPresent(String.self, forKey: .recordFullscreenShortcut)
                ?? "",
            audioOnlyRecording: container.decodeIfPresent(
                String.self, forKey: .audioOnlyRecordingShortcut) ?? "",
            quickRecordLast: container.decodeIfPresent(String.self, forKey: .quickRecordLastShortcut)
                ?? "",
            clipReplayBuffer: container.decodeIfPresent(String.self, forKey: .clipReplayBufferShortcut)
                ?? ""
        )
    }

    private static func decodeGeneralSettings(from container: AppSettingsDecoder) throws
    -> GeneralSettings {
        let quickExportPresetID: UUID?
        if container.contains(.quickExportPresetID) {
            quickExportPresetID = try container.decodeIfPresent(UUID.self, forKey: .quickExportPresetID)
        } else {
            quickExportPresetID = ExportPreset.quickGIFID
        }

        return try GeneralSettings(
            updatePreferences: container.decodeIfPresent(
                UpdatePreferences.self, forKey: .updatePreferences) ?? .defaults,
            showTimeInMenuBar: container.decodeIfPresent(Bool.self, forKey: .showTimeInMenuBar)
                ?? true,
            hideMenuBarIcon: container.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon)
                ?? false,
            launchAtLogin: container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true,
            commandLineToolInstall: container.decodeIfPresent(
                CommandLineToolInstall.self,
                forKey: .commandLineToolInstall
            ),
            commandLineShell: container.decodeIfPresent(
                CommandLineShell.self,
                forKey: .commandLineShell
            ) ?? .zsh,
            notificationReminder: container.decodeIfPresent(Bool.self, forKey: .notificationReminder)
                ?? true,
            urlAutomationGrants: container.decodeIfPresent(
                [String].self, forKey: .urlAutomationGrants) ?? [],
            exportPresets: container.decodeIfPresent(
                [ExportPreset].self, forKey: .exportPresets) ?? ExportPreset.builtInDefaults,
            quickExportPresetID: quickExportPresetID,
            rememberLastCapture: container.decodeIfPresent(Bool.self, forKey: .rememberLastCapture)
                ?? true,
            loupeAlwaysOn: container.decodeIfPresent(Bool.self, forKey: .loupeAlwaysOn) ?? false,
            dimOtherDisplays: container.decodeIfPresent(Bool.self, forKey: .dimOtherDisplays) ?? false,
            restoreLastSelection: container.decodeIfPresent(Bool.self, forKey: .restoreLastSelection)
                ?? true,
            userSizePresets: removingRemovedBuiltInSizePresets(
                from: container.decodeIfPresent([CaptureSizePreset].self, forKey: .userSizePresets)
                    ?? CaptureSizePreset.builtInDefaults
            ),
            lastCaptureMemory: container.decodeIfPresent(
                LastCaptureMemory.self, forKey: .lastCaptureMemory),
            perFormatExportMemory: container.decodeIfPresent(
                [ExportFormat: ExportMemory].self,
                forKey: .perFormatExportMemory
            ) ?? [:],
            lastSelectedExportFormat: container.decodeIfPresent(
                ExportFormat.self,
                forKey: .lastSelectedExportFormat
            ),
            confirmDiscard: container.decodeIfPresent(Bool.self, forKey: .confirmDiscard) ?? true,
            defaultCountdown: container.decodeIfPresent(TimeInterval.self, forKey: .defaultCountdown),
            lastStopAfter: container.decodeIfPresent(TimeInterval.self, forKey: .lastStopAfter)
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
        guard recordingFrameRateRange.contains(framesPerSecond) else {
            throw AppSettingsError.invalidRecordingFrameRate
        }

        return try FrameRate(framesPerSecond)
    }

    static func supportedRecordingFrameRate(_ frameRate: FrameRate?) -> FrameRate? {
        guard let frameRate,
              recordingFrameRateRange.contains(frameRate.framesPerSecond)
        else {
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

private struct AudioInputSettings {
    let id: String?
    let name: String?
}

private struct TranscriptSettings {
    let turnSegmentationEnabled: Bool
    let speakerDiarizationEnabled: Bool
    let languageIdentifier: String?
    let enginePreference: TranscriptEnginePreference
}

private struct CaptureSurfaceSettings {
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

private struct ShortcutSettings {
    let triggerCropper: String
    let toggleRecording: String
    let recordActiveWindow: String
    let recordFullscreen: String
    let audioOnlyRecording: String
    let quickRecordLast: String
    let clipReplayBuffer: String
}

private struct GeneralSettings {
    let updatePreferences: UpdatePreferences
    let showTimeInMenuBar: Bool
    let hideMenuBarIcon: Bool
    let launchAtLogin: Bool
    let commandLineToolInstall: CommandLineToolInstall?
    let commandLineShell: CommandLineShell
    let notificationReminder: Bool
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
