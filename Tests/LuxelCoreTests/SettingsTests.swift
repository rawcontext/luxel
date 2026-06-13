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
        #expect(settings.audioOnlyRecordingShortcut == "")
        #expect(settings.quickRecordLastShortcut == "")
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
        #expect(settings.confirmDiscard)
    }

    @Test("update channels expose settings labels")
    func updateChannelsExposeSettingsLabels() {
        #expect(UpdateChannel.stable.label == "Stable")
        #expect(UpdateChannel.beta.label == "Beta")
    }
}
