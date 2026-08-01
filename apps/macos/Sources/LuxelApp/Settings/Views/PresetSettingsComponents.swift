import LuxelPresentation
import SwiftUI

struct PresetActionButtons: View {
    let isSelectionAvailable: Bool
    let addHelp: String
    let duplicateHelp: String
    let deleteHelp: String
    let add: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: add) {
                SettingsCapsuleButtonLabel("Add", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .help(addHelp)

            Button(action: duplicate) {
                SettingsCapsuleButtonLabel("Duplicate", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)
            .disabled(!isSelectionAvailable)
            .opacity(isSelectionAvailable ? 1 : 0.45)
            .help(duplicateHelp)

            Button(role: .destructive, action: delete) {
                SettingsCapsuleButtonLabel("Delete", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .disabled(!isSelectionAvailable)
            .opacity(isSelectionAvailable ? 1 : 0.45)
            .help(deleteHelp)
        }
        .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }
}

struct PresetNameEditor: View {
    @Binding var name: String
    let help: String

    var body: some View {
        SettingsRow("Name") {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.system(size: 12.5, weight: .medium))
                .multilineTextAlignment(.trailing)
                .frame(width: 180)
                .luxelGlassFieldBackground(cornerRadius: 13)
        }
        .help(help)
    }
}

@MainActor
func makeSelectedPresetBinding<Preset: Identifiable & Sendable>(
    id: Preset.ID?,
    presets: Binding<[Preset]>
) -> Binding<Preset>? {
    guard let id, let index = presets.wrappedValue.firstIndex(where: { $0.id == id }) else {
        return nil
    }
    return Binding(
        get: { presets.wrappedValue[index] },
        set: { presets.wrappedValue[index] = $0 }
    )
}
