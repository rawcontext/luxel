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
        #expect(!settings.record60FPS)
        #expect(settings.loopExports)
        #expect(!settings.recordAudio)
        #expect(settings.audioInputDeviceID == "SYSTEM_DEFAULT")
        #expect(settings.audioInputDeviceName == "System Default")
        #expect(settings.audioOnlyFormat == .aac)
        #expect(settings.enableShortcuts)
        #expect(settings.triggerCropperShortcut == "")
        #expect(settings.toggleRecordingShortcut == "")
        #expect(settings.recordActiveWindowShortcut == "")
        #expect(settings.recordFullscreenShortcut == "")
        #expect(settings.audioOnlyRecordingShortcut == "")
        #expect(settings.quickRecordLastShortcut == "")
        #expect(settings.captureScreenshotShortcut == "")
        #expect(settings.screenshotActiveWindowShortcut == "")
        #expect(settings.screenshotFullscreenShortcut == "")
        #expect(settings.updatePreferences == .defaults)
        #expect(settings.updatePreferences.automaticallyCheckForUpdates)
        #expect(!settings.updatePreferences.automaticallyDownloadAndInstall)
        #expect(settings.updatePreferences.channel == .stable)
        #expect(settings.showTimeInMenuBar)
        #expect(settings.exportPresets == ExportPreset.builtInDefaults)
        #expect(settings.quickExportPresetID == ExportPreset.quickGIFID)
        #expect(settings.rememberLastCapture)
        #expect(settings.lastCaptureMemory == nil)
        #expect(settings.perFormatExportMemory.isEmpty)
        #expect(settings.screenshotFormat == .png)
        #expect(settings.screenshotDestinations == [.clipboard, .file])
        #expect(settings.screenshotShowThumbnail)
        #expect(settings.screenshotBackdrop == .opaque)
        #expect(settings.confirmDiscard)
        #expect(settings.lastStopAfter == nil)
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
