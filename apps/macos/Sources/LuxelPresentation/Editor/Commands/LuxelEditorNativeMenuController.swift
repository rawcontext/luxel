import AppKit

@MainActor
public final class LuxelEditorNativeMenuController: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private let model: LuxelEditorModel
    private let identifierPrefix = "media.luxel.editor."

    public init(model: LuxelEditorModel) {
        self.model = model
        super.init()
    }

    public func install() {
        guard let mainMenu = NSApplication.shared.mainMenu else {
            Task { @MainActor in
                await Task.yield()
                install()
            }
            return
        }

        installEditMenu(in: mainMenu)
        installFileMenu(in: mainMenu)
        installPlaybackMenu(in: mainMenu)
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undoEditorChange):
            model.canUndoEditorChange
        case #selector(redoEditorChange):
            model.canRedoEditorChange
        case #selector(copyCurrentFrame), #selector(saveCurrentFrameAs):
            model.canGrabFrame
        case #selector(saveOriginal):
            model.canSaveOriginal
        case #selector(startExport):
            model.canExport
        case #selector(cancelExport):
            model.canCancelExport
        case #selector(discardRecording):
            model.canDiscard
        case #selector(togglePlayback):
            model.hasSource
        case #selector(openExportedFile),
            #selector(revealExportedFile),
            #selector(saveExportedFileAs),
            #selector(openExportedFileWithApplication),
            #selector(copyExportedFile),
            #selector(copyExportedFilePath),
            #selector(shareExportedFile):
            model.exportedURL != nil
        default:
            true
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        updateExportMenuItems(in: menu)
    }

    private func installEditMenu(in mainMenu: NSMenu) {
        let menu = menu(named: "Edit", in: mainMenu)
        removeInstalledItems(from: menu)
        removeItems(titled: ["Undo", "Redo"], from: menu)

        menu.insertItem(
            item("Undo", action: #selector(undoEditorChange), keyEquivalent: "z"),
            at: 0
        )
        menu.insertItem(
            item("Redo", action: #selector(redoEditorChange), keyEquivalent: "Z"),
            at: 1
        )
        menu.insertItem(separator(), at: 2)
        menu.addItem(separator())
        menu.addItem(item("Copy Frame", action: #selector(copyCurrentFrame), keyEquivalent: "C"))
        menu.delegate = self
    }

    private func installFileMenu(in mainMenu: NSMenu) {
        let menu = menu(named: "File", in: mainMenu)
        removeInstalledItems(from: menu)

        menu.addItem(separator())
        menu.addItem(item("Save Current Frame As...", action: #selector(saveCurrentFrameAs)))
        menu.addItem(item("Save As", action: #selector(saveOriginal)))
        menu.addItem(separator())
        menu.addItem(item("Export", action: #selector(startExport)))
        menu.addItem(item("Cancel Export", action: #selector(cancelExport)))
        menu.addItem(exportedFileItem())
        menu.addItem(separator())
        menu.addItem(item("Discard Recording", action: #selector(discardRecording), keyEquivalent: "d"))
        menu.delegate = self
        updateExportMenuItems(in: menu)
    }

    private func installPlaybackMenu(in mainMenu: NSMenu) {
        let menu = menu(named: "Playback", in: mainMenu)
        removeInstalledItems(from: menu)

        menu.addItem(item("Play/Pause Preview", action: #selector(togglePlayback)))
        menu.delegate = self
    }

    private func exportedFileItem() -> NSMenuItem {
        let exportedItem = NSMenuItem(title: "Exported File", action: nil, keyEquivalent: "")
        exportedItem.identifier = identifier("exportedFile")

        let submenu = NSMenu(title: "Exported File")
        submenu.addItem(item("Open", action: #selector(openExportedFile)))
        submenu.addItem(item("Reveal in Finder", action: #selector(revealExportedFile)))
        submenu.addItem(item("Save a Copy...", action: #selector(saveExportedFileAs)))
        submenu.addItem(item("Open With...", action: #selector(openExportedFileWithApplication)))
        submenu.addItem(separator())
        submenu.addItem(item("Copy File", action: #selector(copyExportedFile)))
        submenu.addItem(item("Copy Path", action: #selector(copyExportedFilePath)))
        submenu.addItem(item("Share...", action: #selector(shareExportedFile)))
        submenu.delegate = self

        exportedItem.submenu = submenu
        return exportedItem
    }

    private func updateExportMenuItems(in menu: NSMenu) {
        for item in menu.items {
            switch item.action {
            case #selector(cancelExport):
                item.isHidden = !model.canCancelExport
            default:
                break
            }

            if item.identifier == identifier("exportedFile") {
                item.isHidden = model.exportedURL == nil
                item.isEnabled = model.exportedURL != nil
            }
        }
    }

    private func menu(named title: String, in mainMenu: NSMenu) -> NSMenu {
        if let item = mainMenu.items.first(where: { $0.title == title }) {
            if let submenu = item.submenu {
                return submenu
            }

            let submenu = NSMenu(title: title)
            item.submenu = submenu
            return submenu
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        item.submenu = submenu
        if title == "File", let editIndex = mainMenu.items.firstIndex(where: { $0.title == "Edit" }) {
            mainMenu.insertItem(item, at: editIndex)
        } else {
            mainMenu.addItem(item)
        }
        return submenu
    }

    private func removeInstalledItems(from menu: NSMenu) {
        for item in menu.items where item.identifier?.rawValue.hasPrefix(identifierPrefix) == true {
            menu.removeItem(item)
        }
    }

    private func removeItems(titled titles: Set<String>, from menu: NSMenu) {
        for item in menu.items where titles.contains(item.title) {
            menu.removeItem(item)
        }
    }

    private func item(
        _ title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.identifier = identifier(title)
        return item
    }

    private func separator() -> NSMenuItem {
        let item = NSMenuItem.separator()
        item.identifier = identifier(UUID().uuidString)
        return item
    }

    private func identifier(_ suffix: String) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("\(identifierPrefix)\(suffix)")
    }

    @objc private func undoEditorChange() {
        model.undoEditorChange()
    }

    @objc private func redoEditorChange() {
        model.redoEditorChange()
    }

    @objc private func copyCurrentFrame() {
        model.copyCurrentFrame()
    }

    @objc private func saveCurrentFrameAs() {
        model.saveCurrentFrameAs()
    }

    @objc private func saveOriginal() {
        model.saveOriginal()
    }

    @objc private func startExport() {
        model.startExport()
    }

    @objc private func cancelExport() {
        model.cancelExport()
    }

    @objc private func discardRecording() {
        guard model.canDiscard else {
            return
        }

        guard !model.confirmDiscard || confirmsDiscardRecording() else {
            return
        }

        if model.discardRecording() {
            NSApplication.shared.keyWindow?.close()
        }
    }

    @objc private func togglePlayback() {
        model.togglePlayback()
    }

    @objc private func openExportedFile() {
        model.openExportedFile()
    }

    @objc private func revealExportedFile() {
        model.revealExportedFile()
    }

    @objc private func saveExportedFileAs() {
        model.saveExportedFileAs()
    }

    @objc private func openExportedFileWithApplication() {
        model.openExportedFileWithApplication()
    }

    @objc private func copyExportedFile() {
        model.copyExportedFile()
    }

    @objc private func copyExportedFilePath() {
        model.copyExportedFilePath()
    }

    @objc private func shareExportedFile() {
        guard let exportedURL = model.exportedURL,
            let contentView = NSApplication.shared.keyWindow?.contentView
        else {
            return
        }

        NSSharingServicePicker(items: [exportedURL])
            .show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
    }

    private func confirmsDiscardRecording() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Discard Recording?"
        alert.informativeText = "Move this recording to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Discard Recording")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask me again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            model.setConfirmDiscard(false)
        }

        return response == .alertFirstButtonReturn
    }
}
