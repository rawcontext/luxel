import Foundation

extension AppSettings {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let cursor = try Self.cursorSettings(from: container); let keys = try Self.shortcutSettings(from: container)
        let recording = try Self.decodeRecordingSettings(from: container)
        let audioInput = try Self.decodeAudioInput(from: container)
        let transcription = try Self.decodeTranscriptionSettings(from: container)
        let capture = try Self.decodeCaptureSurfaceSettings(from: container)
        let general = try Self.decodeGeneralSettings(from: container)
        recordingsDirectory = try container.decode(URL.self, forKey: .recordingsDirectory)
        recordingsDirectoryBookmark = try container.decodeIfPresent(
            BookmarkedDirectory.self, forKey: .recordingsDirectoryBookmark
        )
        showCursor = cursor.showCursor; highlightClicks = cursor.highlightClicks
        cursorMode = cursor.mode; cursorRenderOptions = cursor.renderOptions
        keystrokeOverlayEnabled = cursor.keystrokeOverlayEnabled
        keystrokeLivePreviewEnabled = cursor.keystrokeLivePreviewEnabled
        keystrokeRenderOptions = cursor.keystrokeRenderOptions
        pauseKeystrokeCaptureShortcut = cursor.pauseKeystrokeCaptureShortcut
        record60FPS = recording.records60FPS; recordingFrameRate = recording.frameRate
        matchDisplayFrameRate = recording.matchesDisplayFrameRate; loopExports = recording.loopsExports
        recordSystemAudio = recording.recordsSystemAudio; recordAudio = recording.recordsAudio
        audioInputDeviceID = audioInput.id; audioInputDeviceName = audioInput.name
        audioOnlyFormat = recording.audioOnlyFormat
        transcriptTurnSegmentationEnabled = transcription.turnSegmentationEnabled
        transcriptSpeakerDiarizationEnabled = transcription.speakerDiarizationEnabled
        transcriptLanguageIdentifier = transcription.languageIdentifier
        cameraDeviceID = capture.cameraDeviceID; cameraSeparateTrack = capture.cameraSeparateTrack
        cameraPreviewStyle = capture.cameraPreviewStyle; cameraPreviewPlacements = capture.cameraPreviewPlacements
        replayBufferConfiguration = capture.replayBufferConfiguration
        replayBufferPreferredBufferLength = capture.replayBufferPreferredBufferLength
        replayBufferResumeOnLaunch = capture.replayBufferResumeOnLaunch
        replayBufferConsentAccepted = capture.replayBufferConsentAccepted
        alwaysShowReplayBufferIsland = capture.alwaysShowReplayBufferIsland
        replayClipDestination = capture.replayClipDestination
        notchSurfaceSettings = capture.notchSurfaceSettings; enableShortcuts = capture.enableShortcuts
        triggerCropperShortcut = keys.triggerCropper; toggleRecordingShortcut = keys.toggleRecording
        recordActiveWindowShortcut = keys.recordActiveWindow
        recordFullscreenShortcut = keys.recordFullscreen; audioOnlyRecordingShortcut = keys.audioOnlyRecording
        quickRecordLastShortcut = keys.quickRecordLast; clipReplayBufferShortcut = keys.clipReplayBuffer
        updatePreferences = general.updatePreferences; showTimeInMenuBar = general.showTimeInMenuBar
        hideMenuBarIcon = general.hideMenuBarIcon && notchSurfaceSettings.isEnabled
        launchAtLogin = general.launchAtLogin
        commandLineControlEnabled = general.commandLineControlEnabled
        commandLinePairedClients = general.commandLinePairedClients
        commandLineFolderGrants = general.commandLineFolderGrants
        notificationReminder = general.notificationReminder
        allowURLAutomation = true; urlAutomationGrants = general.urlAutomationGrants
        exportPresets = general.exportPresets; quickExportPresetID = general.quickExportPresetID
        rememberLastCapture = general.rememberLastCapture; loupeAlwaysOn = general.loupeAlwaysOn
        dimOtherDisplays = general.dimOtherDisplays; restoreLastSelection = general.restoreLastSelection
        userSizePresets = general.userSizePresets; lastCaptureMemory = general.lastCaptureMemory
        perFormatExportMemory = general.perFormatExportMemory
        lastSelectedExportFormat = general.lastSelectedExportFormat; confirmDiscard = general.confirmDiscard
        defaultCountdown = general.defaultCountdown; lastStopAfter = general.lastStopAfter
    }

    private static func cursorSettings(from container: AppSettingsDecoder) throws
    -> CursorSettings {
        let showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true
        let highlightClicks = try container.decodeIfPresent(Bool.self, forKey: .highlightClicks) ?? false
        return try CursorSettings(
            showCursor: showCursor,
            highlightClicks: highlightClicks,
            mode: container.decodeIfPresent(CursorMode.self, forKey: .cursorMode)
                ?? cursorMode(showCursor: showCursor),
            renderOptions: container.decodeIfPresent(
                CursorRenderOptions.self,
                forKey: .cursorRenderOptions
            ) ?? cursorRenderOptions(showCursor: showCursor, highlightClicks: highlightClicks),
            keystrokeOverlayEnabled: container.decodeIfPresent(
                Bool.self, forKey: .keystrokeOverlayEnabled
            ) ?? false,
            keystrokeLivePreviewEnabled: container.decodeIfPresent(
                Bool.self, forKey: .keystrokeLivePreviewEnabled
            ) ?? true,
            keystrokeRenderOptions: container.decodeIfPresent(
                KeystrokeRenderOptions.self,
                forKey: .keystrokeRenderOptions
            ) ?? .standard,
            pauseKeystrokeCaptureShortcut: container.decodeIfPresent(
                String.self,
                forKey: .pauseKeystrokeCaptureShortcut
            ) ?? ""
        )
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
            ).flatMap(Self.nonEmpty)
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

    private static func shortcutSettings(from container: AppSettingsDecoder) throws -> ShortcutSettings {
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
        return try GeneralSettings(
            updatePreferences: container.decodeIfPresent(
                UpdatePreferences.self, forKey: .updatePreferences) ?? .defaults,
            showTimeInMenuBar: container.decodeIfPresent(Bool.self, forKey: .showTimeInMenuBar)
                ?? true,
            hideMenuBarIcon: container.decodeIfPresent(Bool.self, forKey: .hideMenuBarIcon)
                ?? false,
            launchAtLogin: container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true,
            commandLineControlEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .commandLineControlEnabled
            ) ?? false,
            commandLinePairedClients: container.decodeIfPresent(
                [CommandLinePairedClient].self,
                forKey: .commandLinePairedClients
            ) ?? [],
            commandLineFolderGrants: container.decodeIfPresent(
                [CommandLineFolderGrant].self,
                forKey: .commandLineFolderGrants
            ) ?? [],
            notificationReminder: container.decodeIfPresent(Bool.self, forKey: .notificationReminder)
                ?? true,
            urlAutomationGrants: container.decodeIfPresent(
                [String].self, forKey: .urlAutomationGrants) ?? [],
            exportPresets: container.decodeIfPresent(
                [ExportPreset].self, forKey: .exportPresets) ?? ExportPreset.builtInDefaults,
            quickExportPresetID: decodeQuickExportPresetID(from: container),
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

    private static func decodeQuickExportPresetID(from container: AppSettingsDecoder) throws -> UUID? {
        guard container.contains(.quickExportPresetID) else {
            return ExportPreset.quickGIFID
        }
        return try container.decodeIfPresent(UUID.self, forKey: .quickExportPresetID)
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
