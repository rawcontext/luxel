import LuxelCore
import SwiftUI

struct CaptureSizePresetSettingsSection: View {
    @Binding var settings: AppSettings
    @State private var selectedPresetID: UUID?

    var body: some View {
        Section("Cropper Sizes") {
            Picker("Edit Size", selection: editPresetSelection) {
                ForEach(settings.userSizePresets) { preset in
                    Text(preset.name).tag(Optional(preset.id))
                }
            }
            .pickerStyle(.menu)
            .disabled(settings.userSizePresets.isEmpty)
            .help("Choose which saved cropper size to edit.")

            HStack {
                Button {
                    addPreset()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Create a new cropper size preset.")

                Button {
                    duplicateSelectedPreset()
                } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .disabled(currentSelectedPresetID == nil)
                .help("Copy the selected cropper size preset.")

                Button(role: .destructive) {
                    deleteSelectedPreset()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(currentSelectedPresetID == nil)
                .help("Delete the selected cropper size preset.")
            }
            .buttonStyle(.bordered)

            if let selectedPresetBinding {
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
        TextField("Name", text: name)
            .help("Name this cropper size preset.")

        Stepper(value: width, in: 1...10_000, step: 10) {
            Text("Width \(preset.pixelSize.width) px")
        }
        .help("Set the preset width in pixels.")

        Stepper(value: height, in: 1...10_000, step: 10) {
            Text("Height \(preset.pixelSize.height) px")
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
