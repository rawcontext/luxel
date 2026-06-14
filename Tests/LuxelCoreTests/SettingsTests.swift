import Foundation
import LuxelCore
import Testing

@Suite("Settings")
struct SettingsTests {
    @Test("default settings match clean-room product defaults")
    func defaultSettings() {
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
        #expect(!settings.record60FPS)
        #expect(settings.loopExports)
        #expect(!settings.recordAudio)
        #expect(settings.audioInputDeviceID == "SYSTEM_DEFAULT")
        #expect(settings.audioInputDeviceName == "System Default")
        #expect(settings.audioOnlyFormat == .aac)
        #expect(settings.cameraDeviceID == nil)
        #expect(settings.cameraSeparateTrack)
        #expect(settings.cameraPreviewStyle == CameraPreviewStyle())
        #expect(settings.cameraPreviewPlacements.isEmpty)
        #expect(settings.cameraRecordingOptions == nil)
        #expect(settings.replayBufferConfiguration == nil)
        #expect(!settings.replayBufferResumeOnLaunch)
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
        #expect(settings.captureScreenshotShortcut == "")
        #expect(settings.screenshotActiveWindowShortcut == "")
        #expect(settings.screenshotFullscreenShortcut == "")
        #expect(settings.updatePreferences == .defaults)
        #expect(settings.updatePreferences.automaticallyCheckForUpdates)
        #expect(!settings.updatePreferences.automaticallyDownloadAndInstall)
        #expect(settings.updatePreferences.channel == .stable)
        #expect(settings.showTimeInMenuBar)
        #expect(settings.notificationReminder)
        #expect(!settings.allowURLAutomation)
        #expect(settings.urlAutomationGrants.isEmpty)
        #expect(settings.exportPresets == ExportPreset.builtInDefaults)
        #expect(settings.quickExportPresetID == ExportPreset.quickGIFID)
        #expect(settings.rememberLastCapture)
        #expect(settings.userSizePresets == CaptureSizePreset.builtInDefaults)
        #expect(settings.lastCaptureMemory == nil)
        #expect(settings.perFormatExportMemory.isEmpty)
        #expect(settings.screenshotFormat == .png)
        #expect(settings.screenshotDestinations == [.clipboard, .file])
        #expect(settings.screenshotShowThumbnail)
        #expect(settings.screenshotBackdrop == .opaque)
        #expect(settings.confirmDiscard)
        #expect(settings.defaultCountdown == nil)
        #expect(settings.lastStopAfter == nil)
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
        #expect(settings.surfacePreferences == NotchSurfacePreferences(
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

        #expect(settings.cameraRecordingOptions == CameraRecordingOptions(
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
        var settings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/Users/example/Movies/Luxel"))

        #expect(throws: ExportPresetSettingsError.presetNotFound(missingID)) {
            _ = try settings.duplicateExportPreset(id: missingID)
        }
    }
}
