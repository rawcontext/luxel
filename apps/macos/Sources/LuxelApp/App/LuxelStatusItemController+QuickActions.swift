import AppKit

@MainActor
extension LuxelStatusItemController {
    func makeStatusItemQuickActionsMenu() -> NSMenu {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings"),
            action: #selector(openSettingsFromStatusItemMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Luxel"),
            action: #selector(quitFromStatusItemMenu),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    func showStatusItemQuickActionsMenu() {
        guard let button = statusItem.button else {
            return
        }

        closePopover()
        makeStatusItemQuickActionsMenu().popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.minX, y: button.bounds.minY),
            in: button
        )
    }

    @objc func openSettingsFromStatusItemMenu() {
        windowPresenter.openSettings(activationSource: activationSourceApplication)
    }

    @objc func quitFromStatusItemMenu() {
        NSApplication.shared.terminate(nil)
    }
}
