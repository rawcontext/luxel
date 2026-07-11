import Foundation
import LuxelCore
import Testing

@Suite("Settings")
struct SettingsTests {
    @Test("transcript engine defaults and missing-key migration stay on Apple Speech")
    func transcriptEngineDefaultsAndMigratesToAppleSpeech() throws {
        let defaults = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(defaults.transcriptEnginePreference == .appleSpeech)

        let data = try JSONSerialization.data(withJSONObject: [
            "recordingsDirectory": "file:///tmp"
        ])
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.transcriptEnginePreference == .appleSpeech)

        var precision = defaults
        precision.transcriptEnginePreference = .precision
        let roundTrip = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(precision)
        )
        #expect(roundTrip.transcriptEnginePreference == .precision)
    }
}

extension SettingsTests {
    @Test("default settings match clean-room product defaults")
    func defaultSettings() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let settings = AppSettings.defaults(recordingsDirectory: directory)

        try assertCaptureDefaults(settings, recordingsDirectory: directory)
        assertProductDefaults(settings)
    }

    private func assertCaptureDefaults(
        _ settings: AppSettings,
        recordingsDirectory: URL
    ) throws {
        #expect(settings.recordingsDirectory == recordingsDirectory)
        #expect(settings.recordingsDirectoryBookmark == nil)
        #expect(settings.showCursor)
        #expect(!settings.highlightClicks)
        #expect(settings.cursorMode == .baked)
        #expect(settings.cursorRenderOptions == .standard)
        #expect(!settings.keystrokeOverlayEnabled)
        #expect(settings.keystrokeLivePreviewEnabled)
        #expect(settings.keystrokeRenderOptions == .standard)
        #expect(settings.pauseKeystrokeCaptureShortcut == "")
        #expect(settings.record60FPS)
        #expect(settings.recordingFrameRate == (try FrameRate(60)))
        #expect(settings.loopExports)
        #expect(settings.recordSystemAudio)
        #expect(!settings.recordAudio)
        #expect(settings.audioInputDeviceID == "SYSTEM_DEFAULT")
        #expect(settings.audioInputDeviceName == "System Default")
        #expect(settings.audioOnlyFormat == .aac)
        #expect(!settings.transcriptTurnSegmentationEnabled)
        #expect(settings.transcriptSpeakerDiarizationEnabled)
        #expect(settings.transcriptLanguageIdentifier == nil)
        #expect(settings.cameraDeviceID == nil)
        #expect(settings.cameraSeparateTrack)
        #expect(settings.cameraPreviewStyle == CameraPreviewStyle())
        #expect(settings.cameraPreviewPlacements.isEmpty)
        #expect(settings.cameraRecordingOptions == nil)
        #expect(settings.replayBufferConfiguration == nil)
        #expect(
            settings.replayBufferPreferredBufferLength == ReplayBufferConfiguration.defaults.bufferLength)
        #expect(!settings.replayBufferResumeOnLaunch)
        #expect(!settings.replayBufferConsentAccepted)
        #expect(!settings.alwaysShowReplayBufferIsland)
        #expect(settings.replayClipDestination == .editor)
    }

    private func assertProductDefaults(_ settings: AppSettings) {
        #expect(settings.notchSurfaceSettings == .defaults)
        #expect(settings.notchSurfacePreferences == .defaults)
        #expect(settings.enableShortcuts)
        #expect(settings.triggerCropperShortcut == "")
        #expect(settings.toggleRecordingShortcut == "")
        #expect(settings.recordActiveWindowShortcut == "")
        #expect(settings.recordFullscreenShortcut == "")
        #expect(settings.audioOnlyRecordingShortcut == "")
        #expect(settings.quickRecordLastShortcut == "")
        #expect(settings.clipReplayBufferShortcut == "")
        #expect(settings.updatePreferences == .defaults)
        #expect(settings.updatePreferences.automaticallyCheckForUpdates)
        #expect(!settings.updatePreferences.automaticallyDownloadAndInstall)
        #expect(settings.updatePreferences.channel == .stable)
        #expect(settings.showTimeInMenuBar)
        #expect(!settings.hideMenuBarIcon)
        #expect(settings.launchAtLogin)
        #expect(settings.commandLineToolInstall == nil)
        #expect(settings.commandLineShell == .zsh)
        #expect(settings.notificationReminder)
        #expect(settings.allowURLAutomation)
        #expect(settings.urlAutomationGrants.isEmpty)
        #expect(settings.exportPresets == ExportPreset.builtInDefaults)
        #expect(settings.quickExportPresetID == ExportPreset.quickGIFID)
        #expect(settings.rememberLastCapture)
        #expect(!settings.loupeAlwaysOn)
        #expect(!settings.dimOtherDisplays)
        #expect(settings.restoreLastSelection)
        #expect(settings.userSizePresets == CaptureSizePreset.builtInDefaults)
        #expect(settings.lastCaptureMemory == nil)
        #expect(settings.perFormatExportMemory.isEmpty)
        #expect(settings.lastSelectedExportFormat == nil)
        #expect(settings.confirmDiscard)
        #expect(settings.defaultCountdown == nil)
        #expect(settings.lastStopAfter == nil)
    }

    @Test("command line shell defaults to zsh when missing")
    func commandLineShellDefaultsToZshWhenMissing() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.commandLineShell == .zsh)
    }

    @Test("transcript turn segmentation setting defaults off and decodes explicit override")
    func transcriptTurnSegmentationSettingDecodesOverride() throws {
        let missingData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
      }
      """.utf8)
        let enabledData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "transcriptTurnSegmentationEnabled": true
      }
      """.utf8)

        #expect(
            !(try JSONDecoder().decode(AppSettings.self, from: missingData)
                .transcriptTurnSegmentationEnabled))
        #expect(
            try JSONDecoder().decode(AppSettings.self, from: enabledData)
                .transcriptTurnSegmentationEnabled)
    }

    @Test("speaker diarization setting defaults on and decodes explicit opt-out")
    func speakerDiarizationSettingDecodesOverride() throws {
        let missingData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
      }
      """.utf8)
        let disabledData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "transcriptSpeakerDiarizationEnabled": false
      }
      """.utf8)

        #expect(
            try JSONDecoder().decode(AppSettings.self, from: missingData)
                .transcriptSpeakerDiarizationEnabled)
        #expect(
            !(try JSONDecoder().decode(AppSettings.self, from: disabledData)
                .transcriptSpeakerDiarizationEnabled))
    }

    @Test("transcript language decodes explicit identifier and treats empty as system default")
    func transcriptLanguageDecodesIdentifier() throws {
        let missingData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
      }
      """.utf8)
        let explicitData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "transcriptLanguageIdentifier": "de-DE"
      }
      """.utf8)
        let emptyData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "transcriptLanguageIdentifier": ""
      }
      """.utf8)

        #expect(
            try JSONDecoder().decode(AppSettings.self, from: missingData)
                .transcriptLanguageIdentifier == nil)
        #expect(
            try JSONDecoder().decode(AppSettings.self, from: explicitData)
                .transcriptLanguageIdentifier == "de-DE")
        #expect(
            try JSONDecoder().decode(AppSettings.self, from: emptyData)
                .transcriptLanguageIdentifier == nil)
    }

    @Test("replay buffer preferred length decodes without enabling buffer")
    func replayBufferPreferredLengthDecodesWithoutEnablingBuffer() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "replayBufferPreferredBufferLength": 300
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.replayBufferConfiguration == nil)
        #expect(settings.replayBufferPreferredBufferLength == 300)
    }

    @Test("replay buffer island visibility defaults off and decodes explicit override")
    func replayBufferIslandVisibilityDefaultsOffAndDecodesOverride() throws {
        let missingData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/"
      }
      """.utf8)
        let enabledData = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "alwaysShowReplayBufferIsland": true
      }
      """.utf8)

        #expect(
            !(try JSONDecoder().decode(AppSettings.self, from: missingData)
                .alwaysShowReplayBufferIsland))
        #expect(
            try JSONDecoder().decode(AppSettings.self, from: enabledData)
                .alwaysShowReplayBufferIsland)
    }

    @Test("replay buffer preferred length falls back to configured buffer length")
    func replayBufferPreferredLengthFallsBackToConfiguredBufferLength() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "replayBufferConfiguration": {
              "bufferLength": 120,
              "source": { "displayWithCursor": {} },
              "frameRate": { "framesPerSecond": 30 },
              "includeSystemAudio": false,
              "quality": "balanced"
          }
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.replayBufferConfiguration?.bufferLength == 120)
        #expect(settings.replayBufferPreferredBufferLength == 120)
    }

    @Test("decoding settings removes retired built-in cropper size presets")
    func decodingSettingsRemovesRetiredBuiltInCropperSizePresets() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "userSizePresets": [
              {
                  "id": "00000000-0000-0000-0000-000000000701",
                  "name": "1280x720",
                  "pixelSize": { "width": 1280, "height": 720 }
              },
              {
                  "id": "00000000-0000-0000-0000-000000000704",
                  "name": "X/Twitter 1280x720",
                  "pixelSize": { "width": 1280, "height": 720 }
              },
              {
                  "id": "00000000-0000-0000-0000-000000000705",
                  "name": "App Store Preview 1920x1080",
                  "pixelSize": { "width": 1920, "height": 1080 }
              },
              {
                  "id": "00000000-0000-0000-0000-000000000806",
                  "name": "Custom X/Twitter",
                  "pixelSize": { "width": 1280, "height": 720 }
              }
          ]
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.userSizePresets.map(\.name) == ["1280x720", "Custom X/Twitter"])
    }

    @Test("camera preview placement rejects non-finite origins")
    func cameraPreviewPlacementRejectsNonFiniteOrigins() {
        #expect(throws: AppSettingsError.invalidCameraPreviewPlacement) {
            _ = try CameraPreviewPlacement(x: .nan, y: 0)
        }

        #expect(throws: AppSettingsError.invalidCameraPreviewPlacement) {
            _ = try CameraPreviewPlacement(x: 0, y: .infinity)
        }
    }

    @Test("recording frame rate setting validates whole-number capture FPS")
    func recordingFrameRateSettingValidatesWholeNumberCaptureFPS() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        var settings = AppSettings.defaults(recordingsDirectory: directory)

        try settings.setRecordingFrameRate(24)

        #expect(settings.recordingFrameRate == (try FrameRate(24)))
        #expect(!settings.record60FPS)

        try settings.setRecordingFrameRate(60)

        #expect(settings.recordingFrameRate == (try FrameRate(60)))
        #expect(settings.record60FPS)

        try settings.setRecordingFrameRate(120)

        #expect(settings.recordingFrameRate == (try FrameRate(120)))
        #expect(!settings.record60FPS)

        #expect(throws: AppSettingsError.invalidRecordingFrameRate) {
            try settings.setRecordingFrameRate(0)
        }
        #expect(throws: AppSettingsError.invalidRecordingFrameRate) {
            try settings.setRecordingFrameRate(121)
        }
        #expect(settings.recordingFrameRate == (try FrameRate(120)))
    }

    @Test("recording display frame rate preference persists")
    func recordingDisplayFrameRatePreferencePersists() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let settings = AppSettings(
            recordingsDirectory: directory,
            recordingFrameRate: try FrameRate(120),
            matchDisplayFrameRate: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(decoded.recordingFrameRate == (try FrameRate(120)))
        #expect(decoded.matchDisplayFrameRate)
    }

    @Test("legacy record 60 FPS setting migrates to typed frame rate")
    func legacyRecord60FPSSettingMigratesToTypedFrameRate() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")

        let settings = AppSettings(recordingsDirectory: directory, record60FPS: true)

        #expect(settings.record60FPS)
        #expect(settings.recordingFrameRate == (try FrameRate(60)))
    }

    @Test("typed recording frame rate wins over legacy boolean when decoding")
    func typedRecordingFrameRateWinsOverLegacyBooleanWhenDecoding() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "record60FPS": true,
          "recordingFrameRate": { "framesPerSecond": 24 }
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.recordingFrameRate == (try FrameRate(24)))
        #expect(!settings.record60FPS)
    }

}
