extension AppSettings {
    mutating func apply(_ cursor: CursorSettings) {
        (showCursor, highlightClicks) = (cursor.showCursor, cursor.highlightClicks)
        (cursorMode, cursorRenderOptions) = (cursor.mode, cursor.renderOptions)
        (keystrokeOverlayEnabled, keystrokeLivePreviewEnabled) =
            (cursor.keystrokeOverlayEnabled, cursor.keystrokeLivePreviewEnabled)
        (keystrokeRenderOptions, pauseKeystrokeCaptureShortcut) =
            (cursor.keystrokeRenderOptions, cursor.pauseKeystrokeCaptureShortcut)
    }

    mutating func apply(
        _ recording: RecordingSettings,
        audioInput: AudioInputSettings
    ) {
        (record60FPS, recordingFrameRate) = (recording.records60FPS, recording.frameRate)
        (matchDisplayFrameRate, loopExports) =
            (recording.matchesDisplayFrameRate, recording.loopsExports)
        (recordSystemAudio, recordAudio) = (recording.recordsSystemAudio, recording.recordsAudio)
        (audioInputDeviceID, audioInputDeviceName) = (audioInput.id, audioInput.name)
        audioOnlyFormat = recording.audioOnlyFormat
    }

    mutating func apply(
        _ transcription: TranscriptSettings,
        speechPromptsEnabled: Bool,
        speechDisclosureAccepted: Bool
    ) {
        (speechDetectionPromptsEnabled, speechDetectionDisclosureAccepted) =
            (speechPromptsEnabled, speechDisclosureAccepted)
        (transcriptTurnSegmentationEnabled, transcriptSpeakerDiarizationEnabled) =
            (transcription.turnSegmentationEnabled, transcription.speakerDiarizationEnabled)
        transcriptLanguageIdentifier = transcription.languageIdentifier
    }

    mutating func apply(_ capture: CaptureSurfaceSettings) {
        (cameraDeviceID, cameraSeparateTrack) = (capture.cameraDeviceID, capture.cameraSeparateTrack)
        (cameraPreviewStyle, cameraPreviewPlacements) =
            (capture.cameraPreviewStyle, capture.cameraPreviewPlacements)
        (replayBufferConfiguration, replayBufferPreferredBufferLength) =
            (capture.replayBufferConfiguration, capture.replayBufferPreferredBufferLength)
        (replayBufferResumeOnLaunch, replayBufferConsentAccepted) =
            (capture.replayBufferResumeOnLaunch, capture.replayBufferConsentAccepted)
        (alwaysShowReplayBufferIsland, replayClipDestination) =
            (capture.alwaysShowReplayBufferIsland, capture.replayClipDestination)
        (notchSurfaceSettings, enableShortcuts) =
            (capture.notchSurfaceSettings, capture.enableShortcuts)
    }

    mutating func apply(_ keys: ShortcutSettings) {
        (triggerCropperShortcut, toggleRecordingShortcut) =
            (keys.triggerCropper, keys.toggleRecording)
        (recordActiveWindowShortcut, recordFullscreenShortcut) =
            (keys.recordActiveWindow, keys.recordFullscreen)
        (audioOnlyRecordingShortcut, quickRecordLastShortcut) =
            (keys.audioOnlyRecording, keys.quickRecordLast)
        clipReplayBufferShortcut = keys.clipReplayBuffer
    }

    mutating func apply(_ general: GeneralSettings) {
        updatePreferences = general.updatePreferences
        (showTimeInMenuBar, hideMenuBarIcon) =
            (general.showTimeInMenuBar, general.hideMenuBarIcon && notchSurfaceSettings.isEnabled)
        (launchAtLogin, commandLineControlEnabled) =
            (general.launchAtLogin, general.commandLineControlEnabled)
        (commandLinePairedClients, commandLineFolderGrants) =
            (general.commandLinePairedClients, general.commandLineFolderGrants)
        (notificationReminder, exportCompletionNotificationsEnabled) =
            (general.notificationReminder, general.exportCompletionNotificationsEnabled)
        (allowURLAutomation, urlAutomationGrants) = (true, general.urlAutomationGrants)
        (exportPresets, quickExportPresetID) = (general.exportPresets, general.quickExportPresetID)
        (rememberLastCapture, loupeAlwaysOn) = (general.rememberLastCapture, general.loupeAlwaysOn)
        (dimOtherDisplays, restoreLastSelection) =
            (general.dimOtherDisplays, general.restoreLastSelection)
        (userSizePresets, lastCaptureMemory) = (general.userSizePresets, general.lastCaptureMemory)
        (perFormatExportMemory, lastSelectedExportFormat) =
            (general.perFormatExportMemory, general.lastSelectedExportFormat)
        (confirmDiscard, defaultCountdown) = (general.confirmDiscard, general.defaultCountdown)
        lastStopAfter = general.lastStopAfter
    }
}
