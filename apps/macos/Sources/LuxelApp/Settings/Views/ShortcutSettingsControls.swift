import AppKit
import LuxelCore
import SwiftUI

struct LuxelShortcutSettingsCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let searchGroup: String
    let selection: Binding<String>
    let defaultRawValue: String

    func matchesSearch(_ query: String) -> Bool {
        guard !query.isEmpty else {
            return true
        }

        let searchableText = "\(title) \(detail) \(searchGroup)".lowercased()
        return searchableText.contains(query.lowercased())
    }
}

struct LuxelShortcutSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search shortcuts"
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchFieldChanged(_:))
        field.setAccessibilityLabel("Search shortcuts")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text

        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @MainActor
        @objc func searchFieldChanged(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
        }

        @MainActor
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }

            text.wrappedValue = field.stringValue
        }
    }
}

struct LuxelShortcutSettingsTable: View {
    let commands: [LuxelShortcutSettingsCommand]
    let allCommands: [LuxelShortcutSettingsCommand]
    let isEnabled: Bool
    let conflictDetector: AppKeyboardShortcutConflictDetector
    @Binding var editingCommandID: String?

    var body: some View {
        VStack(spacing: 0) {
            header

            if commands.isEmpty {
                emptyState
            } else {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    if index > 0 {
                        Divider()
                    }

                    LuxelShortcutSettingsRow(
                        command: command,
                        allCommands: allCommands,
                        isEnabled: isEnabled,
                        conflictDetector: conflictDetector,
                        editingCommandID: $editingCommandID
                    )
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.primary.opacity(0.1), lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.58)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Command")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Keybinding")
                .frame(width: 240, alignment: .leading)

            Color.clear
                .frame(width: 72)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        Text("No shortcuts found")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .overlay(alignment: .top) {
                Divider()
            }
    }
}

private struct LuxelShortcutSettingsRow: View {
    let command: LuxelShortcutSettingsCommand
    let allCommands: [LuxelShortcutSettingsCommand]
    let isEnabled: Bool
    let conflictDetector: AppKeyboardShortcutConflictDetector
    @Binding var editingCommandID: String?
    @State private var recorderMessage: String?

    private var isEditing: Bool {
        editingCommandID == command.id
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            commandColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            keybindingColumn
                .frame(width: 240, alignment: .leading)

            actionColumn
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onChange(of: isEditing) {
            if !isEditing {
                recorderMessage = nil
            }
        }
    }

    private var commandColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command.title)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(command.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var keybindingColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if isEditing {
                    ShortcutRecorderView(
                        onShortcut: recordShortcut,
                        onInvalidShortcut: {
                            recorderMessage = "Use a letter or number with a modifier"
                        },
                        onCancel: cancelEditing
                    )
                    .frame(width: 136, height: 32)

                    Button("Cancel", action: cancelEditing)
                        .buttonStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ShortcutKeybindingLabel(rawValue: command.selection.wrappedValue)

                    shortcutIconButton(
                        systemImage: "pencil",
                        accessibilityLabel: "Change shortcut for \(command.title)",
                        help: "Change shortcut for \(command.title)"
                    ) {
                        editingCommandID = command.id
                    }
                }
            }
            .disabled(!isEnabled)

            Text(shortcutHelperText ?? " ")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .opacity(shortcutHelperText == nil ? 0 : 1)
                .frame(height: 16, alignment: .leading)
        }
    }

    private var actionColumn: some View {
        HStack(spacing: 8) {
            shortcutIconButton(
                systemImage: "trash",
                accessibilityLabel: "Clear shortcut for \(command.title)",
                help: "Clear shortcut for \(command.title)"
            ) {
                command.selection.wrappedValue = ""
                cancelEditing()
            }
            .disabled(!isEnabled || command.selection.wrappedValue.isEmpty)
            .opacity(command.selection.wrappedValue.isEmpty ? 0.35 : 1)

            shortcutIconButton(
                systemImage: "arrow.uturn.backward",
                accessibilityLabel: "Reset shortcut for \(command.title)",
                help: "Reset shortcut for \(command.title)"
            ) {
                command.selection.wrappedValue = command.defaultRawValue
                cancelEditing()
            }
            .disabled(!isEnabled || command.selection.wrappedValue == command.defaultRawValue)
            .opacity(command.selection.wrappedValue == command.defaultRawValue ? 0.35 : 1)
        }
        .opacity(isEditing ? 0 : 1)
        .allowsHitTesting(!isEditing)
    }

    private var shortcutWarning: String? {
        if let duplicate = duplicateCommand(forRawValue: command.selection.wrappedValue) {
            return "Used by \(duplicate.title)"
        }

        if let conflict = conflictDetector.conflict(forRawValue: command.selection.wrappedValue) {
            return "Conflicts with \(conflict.systemAction)"
        }

        return nil
    }

    private var shortcutHelperText: String? {
        isEditing ? recorderMessage : shortcutWarning
    }

    private func recordShortcut(_ shortcut: AppKeyboardShortcut) {
        if let duplicate = duplicateCommand(forRawValue: shortcut.rawValue) {
            recorderMessage = "Used by \(duplicate.title)"
            return
        }

        command.selection.wrappedValue = shortcut.rawValue
        cancelEditing()
    }

    private func duplicateCommand(forRawValue rawValue: String) -> LuxelShortcutSettingsCommand? {
        guard let normalizedRawValue = normalizedShortcutRawValue(rawValue) else {
            return nil
        }

        return allCommands.first { candidate in
            candidate.id != command.id
                && normalizedShortcutRawValue(candidate.selection.wrappedValue) == normalizedRawValue
        }
    }

    private func normalizedShortcutRawValue(_ rawValue: String) -> String? {
        AppKeyboardShortcut(rawValue: rawValue)?.rawValue
    }

    private func cancelEditing() {
        editingCommandID = nil
    }

    private func shortcutIconButton(
        systemImage: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }
}

private struct ShortcutKeybindingLabel: View {
    let rawValue: String

    var body: some View {
        if let shortcut = AppKeyboardShortcut(rawValue: rawValue) {
            Text(shortcut.compactDisplayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.primary.opacity(0.1), in: Capsule())
                .lineLimit(1)
        } else {
            Text("Unassigned")
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct ShortcutRecorderView: NSViewRepresentable {
    let onShortcut: (AppKeyboardShortcut) -> Void
    let onInvalidShortcut: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcut = onShortcut
        view.onInvalidShortcut = onInvalidShortcut
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onInvalidShortcut = onInvalidShortcut
        nsView.onCancel = onCancel
        nsView.requestFocus()
    }
}

private final class ShortcutRecorderNSView: NSView {
    var onShortcut: ((AppKeyboardShortcut) -> Void)?
    var onInvalidShortcut: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = "Press shortcut" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: 14,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - 28,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFocus()
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard handle(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        if event.keyCode == 53 {
            onCancel?()
            return true
        }

        guard let shortcut = event.luxelShortcut else {
            onInvalidShortcut?()
            return true
        }

        onShortcut?(shortcut)
        return true
    }
}

private extension NSEvent {
    var luxelShortcut: AppKeyboardShortcut? {
        guard let rawKey = charactersIgnoringModifiers?.lowercased(),
              rawKey.count == 1,
              let scalar = rawKey.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar) else {
            return nil
        }

        return try? AppKeyboardShortcut(key: rawKey, modifiers: luxelShortcutModifiers)
    }

    var luxelShortcutModifiers: [AppKeyboardShortcutModifier] {
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
