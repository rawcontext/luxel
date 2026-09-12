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
    private var editorPresentationInFlight = false
    private var editorPresentationTask: Task<Void, Never>?

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
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
        model.settingsDisplayFrameRate = (window.screen ?? NSScreen.main)?.maximumFramesPerSecond ?? 60
        refreshEditorMenusIfNeeded()
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
        editorPresentationTask?.cancel()
        editorPresentationInFlight = true
        editorPresentationTask = Task { @MainActor [weak self, weak window, weak activationSource] in
            guard let self, let window else {
                return
            }

            let promotedFromAccessory = await promoteToRegular(
                activationSource: activationSource
            )
            guard !Task.isCancelled else { return }

            present(window, activationSource: activationSource)
            editorPresentationInFlight = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            present(window, activationSource: activationSource)

            if promotedFromAccessory {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
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
            !sourceApplication.isTerminated {
            _ = currentApplication.activate(from: sourceApplication, options: .activateAllWindows)
        } else if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
            frontmostApplication.processIdentifier != currentApplication.processIdentifier {
            _ = currentApplication.activate(from: frontmostApplication, options: .activateAllWindows)
        } else {
            NSApplication.shared.activate()
            _ = currentApplication.activate(options: .activateAllWindows)
        }
    }

    func windowWillClose(_ notification: Notification) {
        pauseEditorPlaybackIfNeeded(for: notification)
    }

    private func pauseEditorPlaybackIfNeeded(for notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
            closingWindow === editorWindow
        else {
            return
        }

        editorModel.pausePlayback()
    }

    @objc private func applicationWindowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow === editorWindow {
            editorPresentationTask?.cancel()
            editorPresentationTask = nil
            editorPresentationInFlight = false
        }
        guard NSApplication.shared.activationPolicy() == .regular,
            !settingsPresentationInFlight,
            !editorPresentationInFlight,
            !NSApplication.shared.windows.contains(where: { window in
                // AppKit posts willClose before removing the window from the screen.
                window !== closingWindow
                    && (window.isMiniaturized || (window.isVisible && window.canBecomeMain))
            })
        else {
            return
        }

        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }
}

struct LuxelSettingsWindowLifecycleObserver: NSViewRepresentable {
    let onWindowDidAppear: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> LuxelSettingsWindowLifecycleView {
        LuxelSettingsWindowLifecycleView(
            onWindowDidAppear: onWindowDidAppear
        )
    }

    func updateNSView(_ nsView: LuxelSettingsWindowLifecycleView, context: Context) {
        nsView.onWindowDidAppear = onWindowDidAppear
        nsView.refreshWindowObservation()
    }
}

@MainActor
final class LuxelSettingsWindowLifecycleView: NSView {
    var onWindowDidAppear: @MainActor (NSWindow) -> Void

    private weak var observedWindow: NSWindow?

    init(
        onWindowDidAppear: @escaping @MainActor (NSWindow) -> Void
    ) {
        self.onWindowDidAppear = onWindowDidAppear
        super.init(frame: .zero)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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

        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
            NotificationCenter.default.removeObserver(self, name: name, object: observedWindow)
        }
        observedWindow = window

        guard let window else {
            return
        }

        onWindowDidAppear(window)
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeScreenNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: name,
                object: window
            )
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        onWindowDidAppear(window)
    }

    @objc private func screenParametersDidChange(_: Notification) {
        guard let window else {
            return
        }

        onWindowDidAppear(window)
    }
}
