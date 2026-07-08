import LuxelCore
import LuxelPresentation
import SwiftUI

struct CaptureSizePresetSettingsSection: View {
    @Binding var settings: AppSettings
    @State private var selectedPresetID: UUID?

    var body: some View {
        SettingsIslandGroup("Cropper Sizes") {
            SettingsRow("Edit Size") {
                SettingsMenuPicker(
                    selection: editPresetSelection,
                    options: settings.userSizePresets.map { Optional($0.id) }
                ) { presetID in
                    presetLabel(presetID)
                }
            }
            .disabled(settings.userSizePresets.isEmpty)
            .opacity(settings.userSizePresets.isEmpty ? 0.45 : 1)
            .help("Choose which saved cropper size to edit.")

            LuxelGlassRowDivider()

            HStack(spacing: 8) {
                Button {
                    addPreset()
                } label: {
                    SettingsCapsuleButtonLabel("Add", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .help("Create a new cropper size preset.")

                Button {
                    duplicateSelectedPreset()
                } label: {
                    SettingsCapsuleButtonLabel("Duplicate", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .disabled(currentSelectedPresetID == nil)
                .opacity(currentSelectedPresetID == nil ? 0.45 : 1)
                .help("Copy the selected cropper size preset.")

                Button(role: .destructive) {
                    deleteSelectedPreset()
                } label: {
                    SettingsCapsuleButtonLabel("Delete", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .disabled(currentSelectedPresetID == nil)
                .opacity(currentSelectedPresetID == nil ? 0.45 : 1)
                .help("Delete the selected cropper size preset.")
            }
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)

            if let selectedPresetBinding {
                LuxelGlassRowDivider()

                CaptureSizePresetEditor(preset: selectedPresetBinding)
            }
        }
        .onAppear {
            repairSelection()
        }
        .onChange(of: settings.userSizePresets.map(\.id)) {
            repairSelection()
        }
    }

    private func presetLabel(_ presetID: UUID?) -> String {
        guard let presetID else {
            return ""
        }

        return settings.userSizePresets.first { $0.id == presetID }?.name ?? ""
    }

    private var editPresetSelection: Binding<UUID?> {
        Binding {
            currentSelectedPresetID
        } set: { presetID in
            selectedPresetID = presetID
        }
    }

    private var currentSelectedPresetID: UUID? {
        if let selectedPresetID,
           settings.userSizePresets.contains(where: { $0.id == selectedPresetID }) {
            return selectedPresetID
        }

        return settings.userSizePresets.first?.id
    }

    private var selectedPresetBinding: Binding<CaptureSizePreset>? {
        guard let selectedPresetID = currentSelectedPresetID,
              let index = settings.userSizePresets.firstIndex(where: { $0.id == selectedPresetID })
        else {
            return nil
        }

        return Binding {
            settings.userSizePresets[index]
        } set: { preset in
            settings.userSizePresets[index] = preset
        }
    }

    private func addPreset() {
        guard let preset = try? settings.addCaptureSizePreset() else {
            return
        }
        selectedPresetID = preset.id
    }

    private func duplicateSelectedPreset() {
        guard let presetID = currentSelectedPresetID,
              let preset = try? settings.duplicateCaptureSizePreset(id: presetID)
        else {
            return
        }
        selectedPresetID = preset.id
    }

    private func deleteSelectedPreset() {
        guard let presetID = currentSelectedPresetID else {
            return
        }
        settings.deleteCaptureSizePreset(id: presetID)
        repairSelection()
    }

    private func repairSelection() {
        selectedPresetID = currentSelectedPresetID
    }
}

private struct CaptureSizePresetEditor: View {
    @Binding var preset: CaptureSizePreset

    var body: some View {
        SettingsRow("Name") {
            TextField("Name", text: name)
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.system(size: 12.5, weight: .medium))
                .multilineTextAlignment(.trailing)
                .frame(width: 180)
                .luxelGlassFieldBackground(cornerRadius: 13)
        }
        .help("Name this cropper size preset.")

        LuxelGlassRowDivider()

        SettingsRow {
            Text(
                LuxelLocalization.format(
                    "settings.captureSize.width",
                    defaultValue: "Width %d px",
                    preset.pixelSize.width)
            )
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))

            Spacer(minLength: 12)

            Stepper(value: width, in: 1...10_000, step: 10) {
                Text(
                    LuxelLocalization.format(
                        "settings.captureSize.width",
                        defaultValue: "Width %d px",
                        preset.pixelSize.width)
                )
            }
            .labelsHidden()
        }
        .help("Set the preset width in pixels.")

        LuxelGlassRowDivider()

        SettingsRow {
            Text(
                LuxelLocalization.format(
                    "settings.captureSize.height",
                    defaultValue: "Height %d px",
                    preset.pixelSize.height)
            )
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))

            Spacer(minLength: 12)

            Stepper(value: height, in: 1...10_000, step: 10) {
                Text(
                    LuxelLocalization.format(
                        "settings.captureSize.height",
                        defaultValue: "Height %d px",
                        preset.pixelSize.height)
                )
            }
            .labelsHidden()
        }
        .help("Set the preset height in pixels.")
    }

    private var name: Binding<String> {
        Binding {
            preset.name
        } set: { name in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            preset.name = trimmedName.isEmpty ? "Untitled Size" : name
        }
    }

    private var width: Binding<Int> {
        Binding {
            preset.pixelSize.width
        } set: { width in
            updatePixelSize(width: width)
        }
    }

    private var height: Binding<Int> {
        Binding {
            preset.pixelSize.height
        } set: { height in
            updatePixelSize(height: height)
        }
    }

    private func updatePixelSize(width: Int? = nil, height: Int? = nil) {
        guard
            let pixelSize = try? PixelSize(
                width: max(1, width ?? preset.pixelSize.width),
                height: max(1, height ?? preset.pixelSize.height)
            )
        else {
            return
        }

        preset.pixelSize = pixelSize
    }
}
