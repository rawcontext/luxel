import Foundation
import LuxelCore
import Testing

@Suite("UserDefaults settings store")
struct UserDefaultsSettingsStoreTests {
    @Test("load returns defaults before settings are saved")
    func loadReturnsDefaultsBeforeSettingsAreSaved() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)

        #expect(try store.load() == defaultSettings)
    }

    @Test("save persists settings")
    func savePersistsSettings() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let settings = try persistedSettings()
        let store = UserDefaultsSettingsStore(userDefaults: defaults, defaultSettings: defaultSettings)

        try store.save(settings)

        let reloadedStore = UserDefaultsSettingsStore(
            userDefaults: defaults, defaultSettings: defaultSettings)
        #expect(try reloadedStore.load() == settings)
    }

    private func persistedSettings() throws -> AppSettings {
        let fixture = try persistedSettingsFixture()

        return AppSettings(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/luxel"),
            recordingsDirectoryBookmark: BookmarkedDirectory(
                url: URL(fileURLWithPath: "/tmp/luxel"), bookmarkData: Data([0x4c, 0x58, 0x4c]),
                accessState: .resolved
            ),
            showCursor: false, highlightClicks: true, cursorMode: .editable,
            cursorRenderOptions: try persistedCursorOptions(),
            keystrokeOverlayEnabled: true, keystrokeLivePreviewEnabled: false,
            keystrokeRenderOptions: try persistedKeystrokeOptions(),
            pauseKeystrokeCaptureShortcut: "command+control+option+k",
            record60FPS: true, recordSystemAudio: true, recordAudio: true,
            audioInputDeviceID: "mic-1", audioInputDeviceName: "Studio Mic",
            audioOnlyFormat: .alac, speechDetectionPromptsEnabled: true,
            speechDetectionDisclosureAccepted: true, transcriptTurnSegmentationEnabled: false,
            cameraDeviceID: "camera-1", cameraSeparateTrack: false,
            cameraPreviewStyle: persistedCameraPreviewStyle(),
            cameraPreviewPlacements: try persistedCameraPreviewPlacements(),
            replayBufferConfiguration: try persistedReplayBufferConfiguration(),
            replayBufferPreferredBufferLength: 120, replayBufferResumeOnLaunch: true,
            replayBufferConsentAccepted: true, alwaysShowReplayBufferIsland: true,
            replayClipDestination: .quickExport,
            notchSurfaceSettings: try persistedNotchSurfaceSettings(),
            triggerCropperShortcut: "command+control+option+r",
            toggleRecordingShortcut: "command+control+option+t",
            recordActiveWindowShortcut: "command+control+option+shift+w",
            recordFullscreenShortcut: "command+control+option+shift+f",
            audioOnlyRecordingShortcut: "command+control+option+a",
            quickRecordLastShortcut: "command+control+option+q",
            clipReplayBufferShortcut: "command+control+option+c",
            updatePreferences: UpdatePreferences(
                automaticallyCheckForUpdates: false,
                automaticallyDownloadAndInstall: false,
                channel: .beta
            ),
            showTimeInMenuBar: false, hideMenuBarIcon: false, launchAtLogin: false,
            commandLineControlEnabled: true,
            commandLinePairedClients: persistedCommandLineClients(),
            commandLineFolderGrants: persistedCommandLineFolderGrants(),
            notificationReminder: false, allowURLAutomation: true,
            urlAutomationGrants: ["com.example.terminal"], exportPresets: [fixture.preset],
            quickExportPresetID: fixture.presetID, rememberLastCapture: false, loupeAlwaysOn: true,
            dimOtherDisplays: true, restoreLastSelection: false,
            userSizePresets: [fixture.sizePreset],
            lastCaptureMemory: try persistedLastCaptureMemory(presetID: fixture.presetID),
            perFormatExportMemory: try persistedExportMemory(),
            lastSelectedExportFormat: .webm, confirmDiscard: false,
            defaultCountdown: 5, lastStopAfter: 60
        )
    }

    private func persistedCommandLineClients() -> [CommandLinePairedClient] {
        [
            CommandLinePairedClient(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
                name: "Terminal",
                pairedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ]
    }

    private func persistedCommandLineFolderGrants() -> [CommandLineFolderGrant] {
        [
            CommandLineFolderGrant(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000404")!,
                directory: BookmarkedDirectory(
                    url: URL(fileURLWithPath: "/tmp/cli", isDirectory: true),
                    bookmarkData: Data([0x63, 0x6c, 0x69])
                ),
                createdAt: Date(timeIntervalSince1970: 1_800_000_001)
            )
        ]
    }

    private func persistedSettingsFixture() throws -> PersistedSettingsFixture {
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        return try PersistedSettingsFixture(
            presetID: presetID,
            preset: persistedExportPreset(id: presetID),
            sizePreset: CaptureSizePreset(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
                name: "Docs 1440p",
                pixelSize: PixelSize(width: 2560, height: 1440)
            )
        )
    }

    private func persistedCameraPreviewStyle() -> CameraPreviewStyle {
        CameraPreviewStyle(
            shape: .square,
            size: .large,
            isMirrored: false,
            backgroundEffect: .portraitCutout
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

}

private struct PersistedSettingsFixture {
    let presetID: UUID
    let preset: ExportPreset
    let sizePreset: CaptureSizePreset
}

extension UserDefaultsSettingsStoreTests {
    @Test("load ignores removed clean-room settings keys")
    func loadIgnoresRemovedCleanRoomSettingsKeys() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let oldPayload = Data(
            """
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

        try assertLegacyCaptureSettings(settings)
        assertLegacyProductSettings(settings)
    }

    private func assertLegacyCaptureSettings(_ settings: AppSettings) throws {
        #expect(settings.recordingsDirectory == URL(fileURLWithPath: "/tmp/luxel/"))
        #expect(settings.recordingsDirectoryBookmark == nil)
        #expect(!settings.showCursor)
        #expect(settings.highlightClicks)
        #expect(settings.cursorMode == .hidden)
        #expect(settings.cursorRenderOptions.isVisible == false)
        #expect(settings.cursorRenderOptions.clickStyle == .ringRipple)
        try expectDefaultKeystrokeAndFrameRateSettings(settings, loopExports: false)
        #expect(settings.recordSystemAudio)
        #expect(settings.recordAudio)
        #expect(settings.audioInputDeviceID == "device-1")
        #expect(settings.audioInputDeviceName == nil)
        #expect(settings.audioOnlyFormat == .aac)
        #expect(!settings.transcriptTurnSegmentationEnabled)
        expectDefaultCameraAndReplaySettings(settings)
        #expect(settings.notchSurfaceSettings == .defaults)
        #expect(settings.notchSurfacePreferences == .defaults)
    }

    private func assertLegacyProductSettings(_ settings: AppSettings) {
    }

    @Test("load preserves explicit nil quick preset")
    func loadPreservesExplicitNilQuickPreset() throws {
        let defaults = makeUserDefaults()
        let defaultSettings = AppSettings.defaults(
            recordingsDirectory: URL(fileURLWithPath: "/tmp/default"))
        let payload = Data(
            """
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
