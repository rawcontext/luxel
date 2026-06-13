import AppKit
import LuxelCore

final class LuxelShortcutController: @unchecked Sendable {
    private let lock = NSLock()
    private var monitors: [Any] = []
    private var shortcut: AppKeyboardShortcut?
    private var action: (@MainActor @Sendable () -> Void)?

    @MainActor
    func configure(
        enabled: Bool,
        rawShortcut: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        removeMonitors()

        let nextShortcut = enabled ? AppKeyboardShortcut(rawValue: rawShortcut) : nil
        lock.lock()
        shortcut = nextShortcut
        self.action = action
        lock.unlock()

        guard nextShortcut != nil else {
            return
        }

        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard self?.handle(event) == true else {
                return event
            }

            return nil
        }) {
            monitors.append(localMonitor)
        }

        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            _ = self?.handle(event)
        }) {
            monitors.append(globalMonitor)
        }
    }

    @MainActor
    func stop() {
        removeMonitors()

        lock.lock()
        shortcut = nil
        action = nil
        lock.unlock()
    }

    private func handle(_ event: NSEvent) -> Bool {
        lock.lock()
        let currentShortcut = shortcut
        let currentAction = action
        lock.unlock()

        guard let currentShortcut, event.matches(currentShortcut) else {
            return false
        }

        if let currentAction {
            Task { @MainActor in
                currentAction()
            }
        }

        return true
    }

    @MainActor
    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }
}

private extension NSEvent {
    func matches(_ shortcut: AppKeyboardShortcut) -> Bool {
        guard type == .keyDown,
              charactersIgnoringModifiers?.lowercased() == shortcut.key else {
            return false
        }

        return Set(appShortcutModifiers) == Set(shortcut.modifiers)
    }

    var appShortcutModifiers: [AppKeyboardShortcutModifier] {
        var modifiers: [AppKeyboardShortcutModifier] = []

        if modifierFlags.contains(.command) {
            modifiers.append(.command)
        }

        if modifierFlags.contains(.control) {
            modifiers.append(.control)
        }

        if modifierFlags.contains(.option) {
            modifiers.append(.option)
        }

        if modifierFlags.contains(.shift) {
            modifiers.append(.shift)
        }

        return modifiers
    }
}
