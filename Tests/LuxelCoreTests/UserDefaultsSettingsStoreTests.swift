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
        let settings = try persistedSettings()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)

        try store.save(settings)

        let reloadedStore = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)
        #expect(try reloadedStore.load() == settings)
    }

    private func persistedSettings() throws -> AppSettings {
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        let preset = try persistedExportPreset(id: presetID)
        let sizePreset = try CaptureSizePreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
            name: "Docs 1440p",
            pixelSize: PixelSize(width: 2560, height: 1440)
        )

        return AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            recordingsDirectoryBookmark: BookmarkedDirectory(
                url: URL(fileURLWithPath: "/tmp/luxel"),
                bookmarkData: Data([0x4c, 0x58, 0x4c]),
                accessState: .resolved
            ),
            showCursor: false,
            highlightClicks: true,
            cursorMode: .editable,
            cursorRenderOptions: try persistedCursorOptions(),
            keystrokeOverlayEnabled: true,
            keystrokeRenderOptions: try persistedKeystrokeOptions(),
            pauseKeystrokeCaptureShortcut: "command+control+option+k",
            record60FPS: true,
            recordAudio: true,
            audioInputDeviceID: "mic-1",
            audioInputDeviceName: "Studio Mic",
            audioOnlyFormat: .alac,
            cameraDeviceID: "camera-1",
            cameraSeparateTrack: false,
            cameraPreviewStyle: CameraPreviewStyle(shape: .roundedRect, size: .large, isMirrored: false),
            cameraPreviewPlacements: try persistedCameraPreviewPlacements(),
            replayBufferConfiguration: try persistedReplayBufferConfiguration(),
            replayBufferResumeOnLaunch: true,
            replayClipDestination: .quickExport,
            notchSurfaceSettings: try persistedNotchSurfaceSettings(),
            triggerCropperShortcut: "command+control+option+r",
            toggleRecordingShortcut: "command+control+option+t",
            recordActiveWindowShortcut: "command+control+option+shift+w",
            recordFullscreenShortcut: "command+control+option+shift+f",
            audioOnlyRecordingShortcut: "command+control+option+a",
            quickRecordLastShortcut: "command+control+option+q",
            clipReplayBufferShortcut: "command+control+option+c",
            captureScreenshotShortcut: "command+control+option+s",
            screenshotActiveWindowShortcut: "command+control+option+w",
            screenshotFullscreenShortcut: "command+control+option+f",
            updatePreferences: UpdatePreferences(
                automaticallyCheckForUpdates: false,
                automaticallyDownloadAndInstall: false,
                channel: .beta
            ),
            showTimeInMenuBar: false,
            notificationReminder: false,
            allowURLAutomation: true,
            urlAutomationGrants: ["com.example.terminal"],
            exportPresets: [preset],
            quickExportPresetID: presetID,
            rememberLastCapture: false,
            loupeAlwaysOn: true,
            dimOtherDisplays: true,
            restoreLastSelection: false,
            userSizePresets: [sizePreset],
            lastCaptureMemory: try persistedLastCaptureMemory(presetID: presetID),
            perFormatExportMemory: try persistedExportMemory(),
            screenshotFormat: .heic,
            screenshotDestinations: [.file, .preview],
            screenshotShowThumbnail: false,
            screenshotBackdrop: .transparentWithShadow,
            confirmDiscard: false,
            defaultCountdown: 5,
            lastStopAfter: 60
        )
    }

    private func persistedExportPreset(id presetID: UUID) throws -> ExportPreset {
        try ExportPreset(
            id: presetID,
            name: "Docs MP4",
            format: .mp4,
            sizeRule: .preset(.percent75),
            frameRate: FrameRate(24),
            destination: .folder(URL(fileURLWithPath: "/tmp/exports")),
            postAction: .revealInFinder
        )
    }

    private func persistedCursorOptions() throws -> CursorRenderOptions {
        try CursorRenderOptions(
            sizeMultiplier: 1.5,
            smoothing: .light,
            clickStyle: .ringRipple
        )
    }

    private func persistedKeystrokeOptions() throws -> KeystrokeRenderOptions {
        try KeystrokeRenderOptions(
            anchor: .topRight,
            size: .large,
            theme: .highContrast,
            displayDuration: 2.25
        )
    }

    private func persistedCameraPreviewPlacements() throws -> [DisplayID: CameraPreviewPlacement] {
        [
            DisplayID(1): try CameraPreviewPlacement(x: 1440.5, y: 92.25),
            DisplayID(7): try CameraPreviewPlacement(x: -320, y: 48)
        ]
    }

    private func persistedReplayBufferConfiguration() throws -> ReplayBufferConfiguration {
        try ReplayBufferConfiguration(
            bufferLength: 120,
            source: .displayWithCursor,
            frameRate: FrameRate(24),
            includeSystemAudio: true,
            quality: .high
        )
    }

    private func persistedNotchSurfaceSettings() throws -> NotchSurfaceSettings {
        try NotchSurfaceSettings(
            isEnabled: false,
            idleHoverActionsEnabled: false,
            showsWaveform: false,
            autoCollapseSeconds: 4.5,
            showsRecentShelf: false,
            fallbackToFloatingHUDWhenUnavailable: false
        )
    }

    private func persistedLastCaptureMemory(presetID: UUID) throws -> LastCaptureMemory {
        try LastCaptureMemory(
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
    }

    private func persistedExportMemory() throws -> [ExportFormat: ExportMemory] {
        [
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
        ]
    }

    @Test("load ignores removed clean-room settings keys")
    func loadIgnoresRemovedCleanRoomSettingsKeys() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let oldPayload = Data("""
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
        """.utf8)
        defaults.set(oldPayload, forKey: "settings")

        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)
        let settings = try store.load()

        #expect(settings.recordingsDirectory == URL(fileURLWithPath: "/tmp/luxel/"))
        #expect(settings.recordingsDirectoryBookmark == nil)
        #expect(!settings.showCursor)
        #expect(settings.highlightClicks)
        #expect(settings.cursorMode == .hidden)
        #expect(settings.cursorRenderOptions.isVisible == false)
        #expect(settings.cursorRenderOptions.clickStyle == .ringRipple)
        #expect(!settings.keystrokeOverlayEnabled)
        #expect(settings.keystrokeRenderOptions == .standard)
        #expect(settings.pauseKeystrokeCaptureShortcut == "")
        #expect(settings.record60FPS)
        #expect(settings.recordingFrameRate == (try FrameRate(60)))
        #expect(!settings.loopExports)
        #expect(settings.recordAudio)
        #expect(settings.audioInputDeviceID == "device-1")
        #expect(settings.audioInputDeviceName == nil)
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
        #expect(!settings.enableShortcuts)
        #expect(settings.triggerCropperShortcut == "command+shift+5")
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
        #expect(settings.showTimeInMenuBar)
        #expect(settings.notificationReminder)
        #expect(!settings.allowURLAutomation)
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
        #expect(settings.screenshotFormat == .png)
        #expect(settings.screenshotDestinations == [.clipboard, .file])
        #expect(settings.screenshotShowThumbnail)
        #expect(settings.screenshotBackdrop == .opaque)
        #expect(settings.confirmDiscard)
        #expect(settings.defaultCountdown == nil)
        #expect(settings.lastStopAfter == nil)
    }

    @Test("load preserves explicit nil quick preset")
    func loadPreservesExplicitNilQuickPreset() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let payload = Data("""
        {
            "recordingsDirectory": "file:///tmp/luxel/",
            "quickExportPresetID": null
        }
        """.utf8)
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
