import Foundation
import LuxelCore
import Testing

@Suite("Settings")
struct SettingsTests {
}

extension SettingsTests {
    @Test("default settings match clean-room product defaults")
    func defaultSettings() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let settings = AppSettings.defaults(recordingsDirectory: directory)

        #expect(settings.recordingsDirectory == directory)
        #expect(settings.recordingsDirectoryBookmark == nil)
        #expect(settings.showCursor)
        #expect(!settings.highlightClicks)
        #expect(settings.cursorMode == .baked)
        #expect(settings.cursorRenderOptions == .standard)
        #expect(!settings.keystrokeOverlayEnabled)
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

        #expect(throws: AppSettingsError.invalidRecordingFrameRate) {
            try settings.setRecordingFrameRate(0)
        }
        #expect(throws: AppSettingsError.invalidRecordingFrameRate) {
            try settings.setRecordingFrameRate(61)
        }
        #expect(settings.recordingFrameRate == (try FrameRate(60)))
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

    @Test("legacy record audio setting enables both audio sources")
    func legacyRecordAudioSettingEnablesBothAudioSources() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "recordAudio": true
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.recordSystemAudio)
        #expect(settings.recordAudio)
    }

    @Test("system and microphone audio settings decode independently")
    func systemAndMicrophoneAudioSettingsDecodeIndependently() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "recordSystemAudio": true,
          "recordAudio": false
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(settings.recordSystemAudio)
        #expect(!settings.recordAudio)
    }

    @Test("notch surface settings validate auto collapse timing")
    func notchSurfaceSettingsValidateAutoCollapseTiming() throws {
        #expect(throws: NotchSurfaceSettingsError.invalidAutoCollapseSeconds) {
            _ = try NotchSurfaceSettings(autoCollapseSeconds: .nan)
        }
        #expect(throws: NotchSurfaceSettingsError.invalidAutoCollapseSeconds) {
            _ = try NotchSurfaceSettings(autoCollapseSeconds: -1)
        }

        let settings = try NotchSurfaceSettings(
            isEnabled: false,
            autoCollapseSeconds: 0,
            fallbackToFloatingHUDWhenUnavailable: false
        )

        #expect(settings.autoCollapseSeconds == 0)
        #expect(
            settings.surfacePreferences
                == NotchSurfacePreferences(
                    isEnabled: false,
                    fallbackToFloatingHUDWhenUnavailable: false
                ))
    }

    @Test("notch surface settings replacement preserves untouched values")
    func notchSurfaceSettingsReplacementPreservesUntouchedValues() throws {
        let settings = try NotchSurfaceSettings(
            isEnabled: true,
            idleHoverActionsEnabled: false,
            showsWaveform: true,
            autoCollapseSeconds: 6,
            showsRecentShelf: true,
            fallbackToFloatingHUDWhenUnavailable: true
        )

        let updated = try settings.replacing(
            showsWaveform: false,
            autoCollapseSeconds: 10
        )

        #expect(updated.isEnabled)
        #expect(!updated.idleHoverActionsEnabled)
        #expect(!updated.showsWaveform)
        #expect(updated.autoCollapseSeconds == 10)
        #expect(updated.showsRecentShelf)
        #expect(updated.fallbackToFloatingHUDWhenUnavailable)
        #expect(throws: NotchSurfaceSettingsError.invalidAutoCollapseSeconds) {
            _ = try settings.replacing(autoCollapseSeconds: .infinity)
        }
    }

    @Test("menu bar icon hiding requires notch surface enabled")
    func menuBarIconHidingRequiresNotchSurfaceEnabled() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        var settings = AppSettings(recordingsDirectory: directory, hideMenuBarIcon: true)

        #expect(settings.hideMenuBarIcon)

        settings.notchSurfaceSettings = try settings.notchSurfaceSettings.replacing(isEnabled: false)

        #expect(!settings.hideMenuBarIcon)
    }

    @Test("decoding menu bar icon hiding respects notch surface state")
    func decodingMenuBarIconHidingRespectsNotchSurfaceState() throws {
        let data = Data(
            """
      {
          "recordingsDirectory": "file:///Users/example/Movies/Luxel/",
          "hideMenuBarIcon": true,
          "notchSurfaceSettings": {
              "isEnabled": false
          }
      }
      """.utf8)

        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(!settings.hideMenuBarIcon)
    }

    @Test("camera recording options derive from camera settings")
    func cameraRecordingOptionsDeriveFromCameraSettings() {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let previewStyle = CameraPreviewStyle(shape: .roundedRect, size: .large, isMirrored: false)
        let settings = AppSettings(
            recordingsDirectory: directory,
            cameraDeviceID: "camera-1",
            cameraSeparateTrack: false,
            cameraPreviewStyle: previewStyle
        )

        #expect(
            settings.cameraRecordingOptions
                == CameraRecordingOptions(
                    deviceID: "camera-1",
                    isEnabled: true,
                    recordsSeparateTrack: false,
                    previewStyle: previewStyle
                ))

        let emptyDeviceSettings = AppSettings(recordingsDirectory: directory, cameraDeviceID: "")
        #expect(emptyDeviceSettings.cameraDeviceID == nil)
        #expect(emptyDeviceSettings.cameraRecordingOptions == nil)
    }

    @Test("legacy cursor toggles keep cursor effect settings synchronized")
    func legacyCursorTogglesKeepCursorEffectSettingsSynchronized() {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        var settings = AppSettings.defaults(recordingsDirectory: directory)

        settings.showCursor = false
        settings.highlightClicks = true

        #expect(settings.cursorMode == .hidden)
        #expect(settings.cursorRenderOptions.isVisible == false)
        #expect(settings.cursorRenderOptions.clickStyle == .ringRipple)

        settings.showCursor = true

        #expect(settings.cursorMode == .baked)
        #expect(settings.cursorRenderOptions.isVisible)
        #expect(settings.cursorRenderOptions.clickStyle == .ringRipple)
    }

    @Test("update channels expose settings labels")
    func updateChannelsExposeSettingsLabels() {
        #expect(UpdateChannel.stable.label == "Stable")
        #expect(UpdateChannel.beta.label == "Beta")
    }

    @Test("adding an export preset creates a unique editable default")
    func addingExportPresetCreatesUniqueEditableDefault() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let existingPreset = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            name: "New Preset",
            format: .gif,
            sizeRule: .maxWidth(960),
            frameRate: FrameRate(30),
            destination: .clipboard,
            postAction: .copyToClipboard
        )
        let newPresetID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
        var settings = AppSettings(
            recordingsDirectory: directory,
            exportPresets: [existingPreset],
            quickExportPresetID: nil
        )

        let preset = try settings.addExportPreset(id: newPresetID)

        #expect(preset.id == newPresetID)
        #expect(preset.name == "New Preset 2")
        #expect(preset.format == .mp4)
        #expect(preset.sizeRule == .original)
        #expect(preset.frameRate == nil)
        #expect(preset.destination == .recordingsDirectory)
        #expect(preset.postAction == .revealInFinder)
        #expect(settings.exportPresets.map(\.id) == [existingPreset.id, newPresetID])
        #expect(settings.quickExportPresetID == newPresetID)
    }

    @Test("duplicating an export preset copies fields with a unique name")
    func duplicatingExportPresetCopiesFieldsWithUniqueName() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
        let copyID = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        let preset = try ExportPreset(
            id: presetID,
            name: "Quick GIF",
            format: .gif,
            sizeRule: .maxWidth(960),
            frameRate: FrameRate(30),
            destination: .clipboard,
            postAction: .copyToClipboard
        )
        let existingCopy = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000505")!,
            name: "Quick GIF Copy",
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .recordingsDirectory,
            postAction: .revealInFinder
        )
        var settings = AppSettings(
            recordingsDirectory: directory,
            exportPresets: [preset, existingCopy],
            quickExportPresetID: preset.id
        )

        let copy = try settings.duplicateExportPreset(id: presetID, newID: copyID)

        #expect(copy.id == copyID)
        #expect(copy.name == "Quick GIF Copy 2")
        #expect(copy.format == preset.format)
        #expect(copy.sizeRule == preset.sizeRule)
        #expect(copy.frameRate == preset.frameRate)
        #expect(copy.destination == preset.destination)
        #expect(copy.postAction == preset.postAction)
        #expect(settings.quickExportPresetID == presetID)
    }

    @Test("deleting the quick export preset falls back to the first remaining preset")
    func deletingQuickExportPresetFallsBackToFirstRemainingPreset() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Movies/Luxel")
        var settings = AppSettings(
            recordingsDirectory: directory,
            exportPresets: ExportPreset.builtInDefaults,
            quickExportPresetID: ExportPreset.quickGIFID
        )

        settings.deleteExportPreset(id: ExportPreset.quickGIFID)

        #expect(settings.exportPresets.map(\.id) == [ExportPreset.quickMP4ID])
        #expect(settings.quickExportPresetID == ExportPreset.quickMP4ID)

        settings.deleteExportPreset(id: ExportPreset.quickMP4ID)

        #expect(settings.exportPresets.isEmpty)
        #expect(settings.quickExportPresetID == nil)
    }

    @Test("duplicating a missing export preset throws")
    func duplicatingMissingExportPresetThrows() {
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000506")!
        var settings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"))

        #expect(throws: ExportPresetSettingsError.presetNotFound(missingID)) {
            _ = try settings.duplicateExportPreset(id: missingID)
        }
    }

    @Test("adding a capture size preset creates a unique editable default")
    func addingCaptureSizePresetCreatesUniqueEditableDefault() throws {
        let existingPreset = try CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000801")!,
            name: "New Size",
            pixelSize: PixelSize(width: 1920, height: 1080)
        )
        let newPresetID = UUID(uuidString: "00000000-0000-0000-0000-000000000802")!
        var settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"),
            userSizePresets: [existingPreset]
        )

        let preset = try settings.addCaptureSizePreset(id: newPresetID)

        #expect(preset.id == newPresetID)
        #expect(preset.name == "New Size 2")
        #expect(preset.pixelSize == (try PixelSize(width: 1280, height: 720)))
        #expect(settings.userSizePresets.map(\.id) == [existingPreset.id, newPresetID])
    }

    @Test("duplicating a capture size preset copies fields with a unique name")
    func duplicatingCaptureSizePresetCopiesFieldsWithUniqueName() throws {
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000803")!
        let copyID = UUID(uuidString: "00000000-0000-0000-0000-000000000804")!
        let preset = try CaptureSizePreset(
            id: presetID,
            name: "X/Twitter",
            pixelSize: PixelSize(width: 1280, height: 720)
        )
        let existingCopy = try CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000805")!,
            name: "X/Twitter Copy",
            pixelSize: PixelSize(width: 800, height: 600)
        )
        var settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"),
            userSizePresets: [preset, existingCopy]
        )

        let copy = try settings.duplicateCaptureSizePreset(id: presetID, newID: copyID)

        #expect(copy.id == copyID)
        #expect(copy.name == "X/Twitter Copy 2")
        #expect(copy.pixelSize == preset.pixelSize)
        #expect(settings.userSizePresets.map(\.id) == [presetID, existingCopy.id, copyID])
    }

    @Test("deleting a capture size preset removes only the matching preset")
    func deletingCaptureSizePresetRemovesOnlyMatchingPreset() throws {
        let first = try CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000806")!,
            name: "First",
            pixelSize: PixelSize(width: 1280, height: 720)
        )
        let second = try CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000807")!,
            name: "Second",
            pixelSize: PixelSize(width: 800, height: 600)
        )
        var settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"),
            userSizePresets: [first, second]
        )

        settings.deleteCaptureSizePreset(id: first.id)

        #expect(settings.userSizePresets == [second])
    }

    @Test("duplicating a missing capture size preset throws")
    func duplicatingMissingCaptureSizePresetThrows() {
        let missingID = UUID(uuidString: "00000000-0000-0000-0000-000000000899")!
        var settings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"))

        #expect(throws: CaptureSizePresetSettingsError.presetNotFound(missingID)) {
            _ = try settings.duplicateCaptureSizePreset(id: missingID)
        }
    }
}
