import Foundation
import LuxelCore
import Testing

@Suite("UserDefaults settings store")
struct UserDefaultsSettingsStoreTests {
    @Test("load returns defaults before settings are saved")
    func loadReturnsDefaultsBeforeSettingsAreSaved() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)

        #expect(try store.load() == defaultSettings)
    }

    @Test("save persists settings")
    func savePersistsSettings() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let preset = try ExportPreset(
            id: presetID,
            name: "Docs MP4",
            format: .mp4,
            sizeRule: .preset(.percent75),
            frameRate: FrameRate(24),
            destination: .folder(URL(fileURLWithPath: "/tmp/exports")),
            postAction: .revealInFinder
        )
        let lastCaptureMemory = try LastCaptureMemory(
            target: .display(DisplayID(7)),
            pixelSize: PixelSize(width: 1920, height: 1080),
            options: RecordingOptions(
                frameRate: 24,
                showCursor: false,
                audio: .system,
                captureKind: .quick(presetID: presetID)
            ),
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let settings = AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            showCursor: false,
            highlightClicks: true,
            record60FPS: true,
            recordAudio: true,
            audioInputDeviceID: "mic-1",
            audioInputDeviceName: "Studio Mic",
            audioOnlyFormat: .alac,
            triggerCropperShortcut: "command+control+option+r",
            toggleRecordingShortcut: "command+control+option+t",
            audioOnlyRecordingShortcut: "command+control+option+a",
            quickRecordLastShortcut: "command+control+option+q",
            updatePreferences: UpdatePreferences(
                automaticallyCheckForUpdates: false,
                automaticallyDownloadAndInstall: false,
                channel: .beta
            ),
            showTimeInMenuBar: false,
            exportPresets: [preset],
            quickExportPresetID: presetID,
            rememberLastCapture: false,
            lastCaptureMemory: lastCaptureMemory,
            perFormatExportMemory: [
                .mp4: try ExportMemory(
                    sizePreset: .percent50,
                    frameRate: FrameRate(24),
                    quality: .high
                ),
                .apng: try ExportMemory(
                    sizePreset: .percent75,
                    frameRate: FrameRate(12),
                    quality: .lossless
                )
            ],
            confirmDiscard: false,
            lastStopAfter: 60
        )
        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)

        try store.save(settings)

        let reloadedStore = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)
        #expect(try reloadedStore.load() == settings)
    }

    @Test("load ignores removed clean-room settings keys")
    func loadIgnoresRemovedCleanRoomSettingsKeys() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let oldPayload = """
        {
            "recordingsDirectory": "file:///tmp/luxel/",
            "allowAnalytics": true,
            "showCursor": false,
            "highlightClicks": true,
            "record60FPS": true,
            "loopExports": false,
            "recordAudio": true,
            "audioInputDeviceID": "device-1",
            "lossyCompression": true,
            "enableShortcuts": false,
            "triggerCropperShortcut": "command+shift+5"
        }
        """.data(using: .utf8)!
        defaults.set(oldPayload, forKey: "settings")

        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)
        let settings = try store.load()

        #expect(settings.recordingsDirectory == URL(fileURLWithPath: "/tmp/luxel/"))
        #expect(!settings.showCursor)
        #expect(settings.highlightClicks)
        #expect(settings.record60FPS)
        #expect(!settings.loopExports)
        #expect(settings.recordAudio)
        #expect(settings.audioInputDeviceID == "device-1")
        #expect(settings.audioInputDeviceName == nil)
        #expect(settings.audioOnlyFormat == .aac)
        #expect(!settings.enableShortcuts)
        #expect(settings.triggerCropperShortcut == "command+shift+5")
        #expect(settings.toggleRecordingShortcut == "")
        #expect(settings.audioOnlyRecordingShortcut == "")
        #expect(settings.quickRecordLastShortcut == "")
        #expect(settings.updatePreferences == .defaults)
        #expect(settings.showTimeInMenuBar)
        #expect(settings.exportPresets == ExportPreset.builtInDefaults)
        #expect(settings.quickExportPresetID == ExportPreset.quickGIFID)
        #expect(settings.rememberLastCapture)
        #expect(settings.lastCaptureMemory == nil)
        #expect(settings.perFormatExportMemory.isEmpty)
        #expect(settings.confirmDiscard)
        #expect(settings.lastStopAfter == nil)
    }

    @Test("load preserves explicit nil quick preset")
    func loadPreservesExplicitNilQuickPreset() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let payload = """
        {
            "recordingsDirectory": "file:///tmp/luxel/",
            "quickExportPresetID": null
        }
        """.data(using: .utf8)!
        defaults.set(payload, forKey: "settings")

        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)
        let settings = try store.load()

        #expect(settings.quickExportPresetID == nil)
        #expect(settings.exportPresets == ExportPreset.builtInDefaults)
    }

    private func makeUserDefaults() -> UserDefaults {
        InMemoryUserDefaults()
    }
}

private final class InMemoryUserDefaults: UserDefaults, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    override func data(forKey defaultName: String) -> Data? {
        storage[defaultName] as? Data
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}
