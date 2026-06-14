import AppKit
import LuxelPresentation
import SwiftUI

@MainActor
final class LuxelWindowPresenter {
    private let model: LuxelMenuModel
    private let editorModel: LuxelEditorModel
    private let cropperPanelController: LuxelCropperPanelController
    private let shortcutController: LuxelShortcutController

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
    }

    func openEditor(fileURL: URL? = nil) {
        let window = editorWindow ?? makeEditorWindow()
        show(window)

        guard let fileURL else {
            return
        }

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(fileURL: fileURL, outputDirectory: model.settings.recordingsDirectory)
        }
    }

    func openSettings() {
        let window = settingsWindow ?? makeSettingsWindow()
        show(window)
    }

    private func makeEditorWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: LuxelEditorView(model: editorModel))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Luxel"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1_000, height: 680))
        window.minSize = NSSize(width: 900, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
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
            .frame(minWidth: 620, minHeight: 640)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Luxel Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 760))
        window.minSize = NSSize(width: 620, height: 640)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        return window
    }

    private func show(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
