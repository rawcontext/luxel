import AppKit
import LuxelPresentation
import SwiftUI

@MainActor
final class LuxelWindowPresenter: NSObject, NSWindowDelegate {
    private let model: LuxelMenuModel
    private let editorModel: LuxelEditorModel
    private let editorMenuController: LuxelEditorNativeMenuController
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?
    private var openSettingsAction: OpenSettingsAction?
    private var pendingSettingsPresentation = false
    private var pendingSettingsActivationSource: NSRunningApplication?
    private var settingsPresentationInFlight = false

    private var editorWindow: NSWindow?
    private weak var settingsWindow: NSWindow?

    init(
        model: LuxelMenuModel,
        editorModel: LuxelEditorModel
    ) {
        self.model = model
        self.editorModel = editorModel
        self.editorMenuController = LuxelEditorNativeMenuController(model: editorModel)
        super.init()
        installMenuRefreshObserver()
    }

    func openEditor(
        fileURL: URL? = nil,
        activationSource: NSRunningApplication? = nil
    ) {
        let window = editorWindow ?? makeEditorWindow()
        show(window, activationSource: activationSource)

        guard let fileURL else {
            return
        }

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(
                fileURL: fileURL,
                outputDirectory: model.settings.recordingsDirectory,
                outputDirectoryBookmark: model.settings.recordingsDirectoryBookmark,
                transcriptSourceContext: model.transcriptSourceContext(for: fileURL)
            )
        }
    }

    func openSettings(activationSource: NSRunningApplication? = nil) {
        guard openSettingsAction != nil else {
            pendingSettingsPresentation = true
            pendingSettingsActivationSource = activationSource
            return
        }

        showSettings(activationSource: activationSource)
    }

    func install(openSettingsAction: OpenSettingsAction) {
        self.openSettingsAction = openSettingsAction

        guard pendingSettingsPresentation else {
            return
        }

        pendingSettingsPresentation = false
        let activationSource = pendingSettingsActivationSource
        pendingSettingsActivationSource = nil
        Task { @MainActor [weak self, weak activationSource] in
            await Task.yield()
            self?.openSettings(activationSource: activationSource)
        }
    }

    func settingsWindowDidAppear(_ window: NSWindow) {
        settingsWindow = window
        settingsPresentationInFlight = false
        refreshEditorMenusIfNeeded()
    }

    func settingsWindowWillClose(_ window: NSWindow) {
        guard window === settingsWindow else {
            return
        }

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.restoreAccessoryActivationPolicyIfNoManagedWindowsVisible()
        }
    }

    private func makeEditorWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: LuxelEditorView(model: editorModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Luxel"
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1_000, height: 680))
        window.minSize = NSSize(width: 900, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        editorWindow = window
        return window
    }

    private func show(
        _ window: NSWindow,
        activationSource: NSRunningApplication?
    ) {
        Task { @MainActor [weak self, weak window, weak activationSource] in
            guard let self, let window else {
                return
            }

            let promotedFromAccessory = await promoteToRegular(
                activationSource: activationSource
            )

            present(window, activationSource: activationSource)
            await Task.yield()
            present(window, activationSource: activationSource)

            if promotedFromAccessory {
                try? await Task.sleep(for: .milliseconds(120))
                present(window, activationSource: activationSource)
            }
        }
    }

    private func showSettings(activationSource: NSRunningApplication?) {
        if settingsWindow?.isVisible != true {
            guard !settingsPresentationInFlight else {
                return
            }
            settingsPresentationInFlight = true
        }

        Task { @MainActor [weak self, weak activationSource] in
            guard let self, let openSettingsAction else {
                return
            }

            _ = await promoteToRegular(activationSource: activationSource)

            editorMenuController.install()
            activateLuxel(from: activationSource)
            openSettingsAction()
            await Task.yield()
            activateLuxel(from: activationSource)
            refreshEditorMenusIfNeeded()
        }
    }

    private func promoteToRegular(
        activationSource: NSRunningApplication?
    ) async -> Bool {
        let promoted = NSApplication.shared.activationPolicy() != .regular
        _ = NSApplication.shared.setActivationPolicy(.regular)
        if promoted {
            yieldActivation(to: activationSource)
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(80))
        }
        return promoted
    }

    private func yieldActivation(to sourceApplication: NSRunningApplication?) {
        guard let sourceApplication,
            sourceApplication.processIdentifier != NSRunningApplication.current.processIdentifier,
            !sourceApplication.isTerminated
        else {
            return
        }

        NSApplication.shared.yieldActivation(to: sourceApplication)
        _ = sourceApplication.activate(options: [])
    }

    private func present(
        _ window: NSWindow,
        activationSource: NSRunningApplication?
    ) {
        LuxelGlassWindowChrome.configure(window)
        editorMenuController.install()
        activateLuxel(from: activationSource)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeMain()
        _ = window.makeFirstResponder(window.contentView)
    }

    private func installMenuRefreshObserver() {
        applicationDidBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshEditorMenusIfNeeded()
            }
        }
    }

    private func refreshEditorMenusIfNeeded() {
        guard NSApplication.shared.activationPolicy() == .regular,
            editorWindow?.isVisible == true || settingsWindow?.isVisible == true
        else {
            return
        }

        editorMenuController.install()
    }

    nonisolated func windowDidBecomeKey(_: Notification) {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.configureManagedWindowChrome()
            self?.refreshEditorMenusIfNeeded()
        }
    }

    private func configureManagedWindowChrome() {
        if let editorWindow, editorWindow.isVisible {
            LuxelGlassWindowChrome.configure(editorWindow)
        }
    }

    private func activateLuxel(from sourceApplication: NSRunningApplication?) {
        NSApplication.shared.unhide(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let currentApplication = NSRunningApplication.current
        if let sourceApplication,
            sourceApplication.processIdentifier != currentApplication.processIdentifier,
            !sourceApplication.isTerminated
        {
            _ = currentApplication.activate(from: sourceApplication, options: .activateAllWindows)
        } else if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier != currentApplication.processIdentifier
        {
            _ = currentApplication.activate(from: frontmostApplication, options: .activateAllWindows)
        } else {
            NSApplication.shared.activate()
            _ = currentApplication.activate(options: .activateAllWindows)
        }
    }

    func windowWillClose(_ notification: Notification) {
        pauseEditorPlaybackIfNeeded(for: notification)

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.restoreAccessoryActivationPolicyIfNoManagedWindowsVisible()
        }
    }

    private func pauseEditorPlaybackIfNeeded(for notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
            closingWindow === editorWindow
        else {
            return
        }

        editorModel.pausePlayback()
    }

    private func restoreAccessoryActivationPolicyIfNoManagedWindowsVisible() {
        guard !settingsPresentationInFlight,
            !NSApplication.shared.windows.contains(where: { window in
                window.isVisible && window.canBecomeMain
            })
        else {
            return
        }

        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }
}

struct LuxelSettingsWindowLifecycleObserver: NSViewRepresentable {
    let onWindowDidAppear: @MainActor (NSWindow) -> Void
    let onWindowWillClose: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> LuxelSettingsWindowLifecycleView {
        LuxelSettingsWindowLifecycleView(
            onWindowDidAppear: onWindowDidAppear,
            onWindowWillClose: onWindowWillClose
        )
    }

    func updateNSView(_ nsView: LuxelSettingsWindowLifecycleView, context: Context) {
        nsView.onWindowDidAppear = onWindowDidAppear
        nsView.onWindowWillClose = onWindowWillClose
        nsView.refreshWindowObservation()
    }
}

@MainActor
final class LuxelSettingsWindowLifecycleView: NSView {
    var onWindowDidAppear: @MainActor (NSWindow) -> Void
    var onWindowWillClose: @MainActor (NSWindow) -> Void

    private weak var observedWindow: NSWindow?

    init(
        onWindowDidAppear: @escaping @MainActor (NSWindow) -> Void,
        onWindowWillClose: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.onWindowDidAppear = onWindowDidAppear
        self.onWindowWillClose = onWindowWillClose
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshWindowObservation()
    }

    func refreshWindowObservation() {
        guard observedWindow !== window else {
            return
        }

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: observedWindow
        )
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: observedWindow
        )
        observedWindow = window

        guard let window else {
            return
        }

        onWindowDidAppear(window)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        onWindowDidAppear(window)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        onWindowWillClose(window)
    }
}
