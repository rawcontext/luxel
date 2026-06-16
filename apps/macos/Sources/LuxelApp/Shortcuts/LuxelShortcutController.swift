import AppKit
import LuxelCore

struct LuxelShortcutRegistration {
    let rawShortcut: String
    let action: @MainActor () -> Void
}

final class LuxelShortcutController: @unchecked Sendable {
    private typealias ShortcutAction = (shortcut: AppKeyboardShortcut, action: @MainActor () -> Void)

    private let lock = NSLock()
    private var monitors: [Any] = []
    private var registrations: [ShortcutAction] = []

    @MainActor
    func configure(
        enabled: Bool,
        registrations nextRegistrations: [LuxelShortcutRegistration]
    ) {
        removeMonitors()

        let nextRegistrations = enabled
            ? nextRegistrations.compactMap { registration -> ShortcutAction? in
                guard let shortcut = AppKeyboardShortcut(rawValue: registration.rawShortcut) else {
                    return nil
                }

                return (shortcut, registration.action)
            }
            : []

        lock.lock()
        registrations = nextRegistrations
        lock.unlock()

        guard !nextRegistrations.isEmpty else {
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
        registrations = []
        lock.unlock()
    }

    private func handle(_ event: NSEvent) -> Bool {
        lock.lock()
        let currentRegistrations = registrations
        lock.unlock()

        guard let registration = currentRegistrations.first(where: { event.matches($0.shortcut) }) else {
            return false
        }

        Task { @MainActor in
            registration.action()
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
