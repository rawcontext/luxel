import AppKit
import LuxelPresentation
import SwiftUI

@MainActor
final class LuxelWindowPresenter: NSObject, NSWindowDelegate {
    private let model: LuxelMenuModel
    private let editorModel: LuxelEditorModel
    private let cropperPanelController: LuxelCropperPanelController
    private let shortcutController: LuxelShortcutController
    private let editorMenuController: LuxelEditorNativeMenuController
    private var applicationDidBecomeActiveObserver: NSObjectProtocol?

    private var editorWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(
        model: LuxelMenuModel,
        editorModel: LuxelEditorModel,
        cropperPanelController: LuxelCropperPanelController,
        shortcutController: LuxelShortcutController
    ) {
        self.model = model
        self.editorModel = editorModel
        self.cropperPanelController = cropperPanelController
        self.shortcutController = shortcutController
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
            await editorModel.open(fileURL: fileURL, outputDirectory: model.settings.recordingsDirectory)
        }
    }

    func openSettings(activationSource: NSRunningApplication? = nil) {
        let window = settingsWindow ?? makeSettingsWindow()
        show(window, activationSource: activationSource)
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

    private func makeSettingsWindow() -> NSWindow {
        let hostingController = NSHostingController(
            rootView: LuxelSettingsView(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController,
                openEditorWindow: { [weak self] in
                    self?.openEditor()
                }
            )
            .frame(minWidth: 840, minHeight: 660)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Luxel Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 760))
        window.minSize = NSSize(width: 840, height: 660)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
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

            let promotedFromAccessory = NSApplication.shared.activationPolicy() != .regular
            _ = NSApplication.shared.setActivationPolicy(.regular)

            if promotedFromAccessory {
                yieldActivation(to: activationSource)
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(80))
            }

            present(window, activationSource: activationSource)
            await Task.yield()
            present(window, activationSource: activationSource)

            if promotedFromAccessory {
                try? await Task.sleep(for: .milliseconds(120))
                present(window, activationSource: activationSource)
            }
        }
    }

    private func yieldActivation(to sourceApplication: NSRunningApplication?) {
        guard let sourceApplication,
              sourceApplication.processIdentifier != NSRunningApplication.current.processIdentifier,
              !sourceApplication.isTerminated else {
            return
        }

        NSApplication.shared.yieldActivation(to: sourceApplication)
        _ = sourceApplication.activate(options: [])
    }

    private func present(
        _ window: NSWindow,
        activationSource: NSRunningApplication?
    ) {
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
              editorWindow?.isVisible == true || settingsWindow?.isVisible == true else {
            return
        }

        editorMenuController.install()
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.refreshEditorMenusIfNeeded()
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

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.restoreAccessoryActivationPolicyIfNoManagedWindowsVisible()
        }
    }

    private func restoreAccessoryActivationPolicyIfNoManagedWindowsVisible() {
        guard editorWindow?.isVisible != true,
              settingsWindow?.isVisible != true else {
            return
        }

        _ = NSApplication.shared.setActivationPolicy(.accessory)
    }
}
