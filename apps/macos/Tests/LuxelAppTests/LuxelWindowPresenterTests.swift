import AppKit
import LuxelCore
import Testing

@testable import LuxelApp

@MainActor
@Suite(.serialized)
struct LuxelWindowPresenterTests {
    @Test("closing an auxiliary window last removes the Dock icon")
    func closingAuxiliaryWindowLastRestoresAccessoryPolicy() async throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let originalMenu = application.mainMenu
        application.mainMenu = NSMenu()
        let presenter = makePresenter()
        let settings = makeWindow()
        let auxiliary = makeWindow()
        defer {
            settings.close()
            auxiliary.close()
            application.mainMenu = originalMenu
            _ = application.setActivationPolicy(originalPolicy)
            withExtendedLifetime(presenter) {}
        }

        _ = application.setActivationPolicy(.regular)
        settings.orderFrontRegardless()
        auxiliary.orderFrontRegardless()
        presenter.settingsWindowDidAppear(settings)
        settings.delegate = presenter
        settings.close()
        try await Task.sleep(for: .milliseconds(50))
        #expect(application.activationPolicy() == .regular)

        auxiliary.close()
        try await Task.sleep(for: .milliseconds(50))
        #expect(application.activationPolicy() == .accessory)
    }

    @Test("a closing window is excluded before AppKit hides it")
    func closingWindowDoesNotKeepDockIconVisible() async throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let presenter = makePresenter()
        let window = makeWindow()
        defer {
            window.close()
            _ = application.setActivationPolicy(originalPolicy)
            withExtendedLifetime(presenter) {}
        }

        _ = application.setActivationPolicy(.regular)
        window.orderFrontRegardless()
        #expect(window.isVisible)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        try await Task.sleep(for: .milliseconds(50))
        #expect(application.activationPolicy() == .accessory)
    }

    @Test("closing another window preserves access to a minimized window in the Dock")
    func minimizedWindowKeepsDockIconVisible() async throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let presenter = makePresenter()
        let minimized = makeWindow()
        let closing = makeWindow()
        defer {
            minimized.close()
            closing.close()
            _ = application.setActivationPolicy(originalPolicy)
            withExtendedLifetime(presenter) {}
        }

        _ = application.setActivationPolicy(.regular)
        minimized.orderFrontRegardless()
        minimized.miniaturize(nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !minimized.isMiniaturized && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(minimized.isMiniaturized)
        closing.orderFrontRegardless()
        closing.close()
        try await Task.sleep(for: .milliseconds(50))
        #expect(application.activationPolicy() == .regular)

        minimized.close()
        try await Task.sleep(for: .milliseconds(50))
        #expect(application.activationPolicy() == .accessory)
    }

    @Test("closing an auxiliary window during editor presentation keeps the Dock icon")
    func editorPresentationKeepsDockIconVisible() async throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let originalMenu = application.mainMenu
        application.mainMenu = NSMenu()
        let presenter = makePresenter()
        let auxiliary = makeWindow()
        defer {
            for window in application.windows where window.delegate === presenter {
                window.close()
            }
            auxiliary.close()
            application.mainMenu = originalMenu
            _ = application.setActivationPolicy(originalPolicy)
        }

        _ = application.setActivationPolicy(.accessory)
        auxiliary.orderFrontRegardless()
        presenter.openEditor()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while application.activationPolicy() != .regular && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(application.activationPolicy() == .regular)
        auxiliary.close()
        try await Task.sleep(for: .milliseconds(300))

        #expect(application.windows.contains { $0.delegate === presenter && $0.isVisible })
        #expect(application.activationPolicy() == .regular)
    }

    @Test("repeated editor requests reuse one window, including after closing")
    func repeatedEditorRequestsReuseOneWindow() async throws {
        let application = NSApplication.shared
        let originalPolicy = application.activationPolicy()
        let originalMenu = application.mainMenu
        application.mainMenu = NSMenu()
        let presenter = makePresenter()
        var editorWindow: NSWindow?
        defer {
            editorWindow?.close()
            application.mainMenu = originalMenu
            _ = application.setActivationPolicy(originalPolicy)
        }

        for _ in 0..<3 {
            presenter.openEditor()
            presenter.openEditor()
            try await Task.sleep(for: .milliseconds(300))
            let windows = application.windows.filter { $0.delegate === presenter && $0.isVisible }
            #expect(windows.count == 1)
            let window = try #require(windows.first)
            if let editorWindow {
                #expect(window === editorWindow)
            }
            editorWindow = window
            #expect(application.activationPolicy() == .regular)

            window.close()
            #expect(!window.isVisible)
            #expect(application.activationPolicy() == .accessory)
        }
    }

    private func makePresenter() -> LuxelWindowPresenter {
        LuxelWindowPresenter(
            model: LuxelMenuModel(settingsStore: WindowPresenterSettingsStore()),
            editorModel: LuxelEditorModelTests().makeModel()
        )
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct WindowPresenterSettingsStore: SettingsStore {
    func load() throws -> AppSettings {
        AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/LuxelWindowPresenterTests"))
    }

    func save(_ settings: AppSettings) throws {}
}
