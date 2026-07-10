import AppKit
import LuxelCore
import LuxelPresentation
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

struct LuxelShortcutSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))

            TextField("Search shortcuts", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.black.opacity(0.3), .white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .accessibilityLabel("Search shortcuts")
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
                        LuxelGlassRowDivider()
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
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.black.opacity(0.16))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
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
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        Text("No shortcuts found")
            .font(.system(size: 12.5))
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .overlay(alignment: .top) {
                LuxelGlassRowDivider()
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
    @State private var isHovered = false

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
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(isHovered ? 0.07 : 0))
                .padding(.horizontal, 6)
        }
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onChange(of: isEditing) {
            if !isEditing {
                recorderMessage = nil
            }
        }
    }

    private var commandColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(command.title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)

            Text(command.detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
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
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
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
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 30, height: 30)
                .background(
                    .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }
}
