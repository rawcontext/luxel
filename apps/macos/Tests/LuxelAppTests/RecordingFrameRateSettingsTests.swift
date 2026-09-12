import AppKit
import LuxelCore
import Testing

@testable import LuxelApp

@MainActor
struct RecordingFrameRateSettingsTests {
    @Test("matching shows the display rate and preserves the manual rate", arguments: [60, 120, 144])
    func matchingShowsDisplayFrameRate(displayFrameRate: Int) throws {
        let model = LuxelMenuModel(settingsStore: FrameRateSettingsStore())
        try model.settings.setRecordingFrameRate(24)
        model.settingsDisplayFrameRate = displayFrameRate
        let view = LuxelSettingsView(
            model: model,
            editorModel: LuxelEditorModelTests().makeModel(),
            cropperPanelController: LuxelCropperPanelController(),
            shortcutController: LuxelShortcutController(),
            openEditorWindow: {}
        )

        model.settings.matchDisplayFrameRate = false
        #expect(view.recordingFrameRateSelection.wrappedValue == 24)

        model.settings.matchDisplayFrameRate = true
        #expect(view.recordingFrameRateSelection.wrappedValue == displayFrameRate)
        #expect(model.settings.recordingFrameRate == (try FrameRate(24)))

        model.settingsDisplayFrameRate = 75
        #expect(view.recordingFrameRateSelection.wrappedValue == 75)

        model.settings.matchDisplayFrameRate = false
        #expect(view.recordingFrameRateSelection.wrappedValue == 24)
    }

    @Test("settings refresh the displayed rate when their screen changes")
    func screenChangesRefreshFrameRate() {
        let model = LuxelMenuModel(settingsStore: FrameRateSettingsStore())
        let presenter = LuxelWindowPresenter(
            model: model,
            editorModel: LuxelEditorModelTests().makeModel()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = LuxelSettingsWindowLifecycleView(onWindowDidAppear: presenter.settingsWindowDidAppear)
        window.contentView = view
        let expectedFrameRate = (window.screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60
        #expect(model.settingsDisplayFrameRate == expectedFrameRate)

        for name in [NSWindow.didChangeScreenNotification, NSApplication.didChangeScreenParametersNotification] {
            model.settingsDisplayFrameRate = 1
            NotificationCenter.default.post(name: name, object: window)
            #expect(model.settingsDisplayFrameRate == expectedFrameRate)
        }

        window.contentView = nil
        model.settingsDisplayFrameRate = 1
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: window)
        #expect(model.settingsDisplayFrameRate == 1)
    }
}

private struct FrameRateSettingsStore: SettingsStore {
    func load() throws -> AppSettings {
        AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/LuxelFrameRateTests"))
    }

    func save(_ settings: AppSettings) throws {}
}
