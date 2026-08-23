import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

struct ExportPresetSettingsSection: View {
    @Binding var settings: AppSettings
    @State private var selectedPresetID: UUID?

    var body: some View {
        Group {
            SettingsIslandGroup("Quick Recording") {
                SettingsRow("Quick Preset") {
                    SettingsMenuPicker(
                        selection: $settings.quickExportPresetID,
                        options: quickPresetOptions
                    ) { presetID in
                        quickPresetLabel(presetID)
                    }
                }
                .help("Choose the preset used by quick recording.")

                LuxelGlassRowDivider()

                Toggle("Remember Last Capture", isOn: $settings.rememberLastCapture)
                    .toggleStyle(LuxelGlassSwitchToggleStyle())
                    .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
                    .help("Reuse the last capture target for quick recording.")
            }

            SettingsIslandGroup("Presets") {
                SettingsRow("Edit Preset") {
                    SettingsMenuPicker(
                        selection: editPresetSelection,
                        options: settings.exportPresets.map { Optional($0.id) }
                    ) { presetID in
                        presetLabel(presetID)
                    }
                }
                .disabled(settings.exportPresets.isEmpty)
                .opacity(settings.exportPresets.isEmpty ? 0.45 : 1)
                .help("Choose which export preset to edit.")

                LuxelGlassRowDivider()

                PresetActionButtons(
                    isSelectionAvailable: currentSelectedPresetID != nil,
                    addHelp: "Create a new export preset.",
                    duplicateHelp: "Copy the selected export preset.",
                    deleteHelp: "Delete the selected export preset.",
                    add: addPreset,
                    duplicate: duplicateSelectedPreset,
                    delete: deleteSelectedPreset
                )

                if let selectedPresetBinding {
                    LuxelGlassRowDivider()

                    ExportPresetEditor(preset: selectedPresetBinding)
                }
            }
        }
        .onAppear {
            repairSelection()
        }
        .onChange(of: settings.exportPresets.map(\.id)) {
            repairSelection()
        }
    }

    private var quickPresetOptions: [UUID?] {
        [nil] + settings.exportPresets.map { Optional($0.id) }
    }

    private func quickPresetLabel(_ presetID: UUID?) -> String {
        guard let presetID,
            let preset = settings.exportPresets.first(where: { $0.id == presetID })
        else {
            return "None"
        }

        return preset.name
    }

    private func presetLabel(_ presetID: UUID?) -> String {
        guard let presetID else {
            return ""
        }

        return settings.exportPresets.first { $0.id == presetID }?.name ?? ""
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
            settings.exportPresets.contains(where: { $0.id == selectedPresetID })
        {
            return selectedPresetID
        }

        if let quickExportPresetID = settings.quickExportPresetID,
            settings.exportPresets.contains(where: { $0.id == quickExportPresetID })
        {
            return quickExportPresetID
        }

        return settings.exportPresets.first?.id
    }

    private var selectedPresetBinding: Binding<ExportPreset>? {
        makeSelectedPresetBinding(id: currentSelectedPresetID, presets: $settings.exportPresets)
    }

    private func addPreset() {
        guard let preset = try? settings.addExportPreset() else {
            return
        }
        selectedPresetID = preset.id
    }

    private func duplicateSelectedPreset() {
        guard let presetID = currentSelectedPresetID,
            let preset = try? settings.duplicateExportPreset(id: presetID)
        else {
            return
        }
        selectedPresetID = preset.id
    }

    private func deleteSelectedPreset() {
        guard let presetID = currentSelectedPresetID else {
            return
        }
        settings.deleteExportPreset(id: presetID)
        repairSelection()
    }

    private func repairSelection() {
        selectedPresetID = currentSelectedPresetID
    }
}

private struct ExportPresetEditor: View {
    @Binding var preset: ExportPreset

    var body: some View {
        Group {
            PresetNameEditor(name: name, help: "Name this export preset.")

            LuxelGlassRowDivider()

            SettingsRow("Format") {
                SettingsMenuPicker(
                    selection: $preset.format,
                    options: ExportFormat.appleNativeV1Formats
                ) { format in
                    format.prettyName
                }
            }
            .help("Choose the export file format.")

            LuxelGlassRowDivider()

            SettingsRow("Size") {
                SettingsMenuPicker(
                    selection: sizeSelection,
                    options: Array(PresetSizeSelection.allCases)
                ) { selection in
                    selection.label
                }
            }
            .help("Choose how much to resize exported video.")
        }

        if case .maxWidth = preset.sizeRule {
            LuxelGlassRowDivider()

            SettingsRow {
                Text(
                    LuxelLocalization.format(
                        "settings.exportPreset.maxWidth",
                        defaultValue: "Max Width %d px",
                        maxWidth.wrappedValue)
                )
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))

                Spacer(minLength: 12)

                Stepper(value: maxWidth, in: 1...10_000, step: 10) {
                    Text(
                        LuxelLocalization.format(
                            "settings.exportPreset.maxWidth",
                            defaultValue: "Max Width %d px",
                            maxWidth.wrappedValue)
                    )
                }
                .labelsHidden()
            }
            .help("Set the maximum exported width in pixels.")
        }

        Group {
            LuxelGlassRowDivider()

            SettingsRow("Frame Rate") {
                SettingsMenuPicker(
                    selection: frameRateSelection,
                    options: frameRateChoices
                ) { frameRate in
                    frameRate == 0 ? "Source" : "\(frameRate) FPS"
                }
            }
            .help("Choose the exported video frame rate.")

            LuxelGlassRowDivider()

            SettingsRow("Destination") {
                SettingsMenuPicker(
                    selection: destinationSelection,
                    options: Array(PresetDestinationSelection.allCases)
                ) { destination in
                    destination.label
                }
            }
            .help("Choose where the exported result goes.")

            LuxelGlassRowDivider()

            SettingsRow("After Export") {
                SettingsMenuPicker(
                    selection: postActionSelection,
                    options: Array(ExportPresetPostAction.allCases)
                ) { action in
                    action.label
                }
            }
            .disabled(preset.destination == .clipboard)
            .opacity(preset.destination == .clipboard ? 0.45 : 1)
            .help("Choose what Luxel does after exporting.")
        }
    }

    private var name: Binding<String> {
        Binding {
            preset.name
        } set: { name in
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            preset.name = trimmedName.isEmpty ? "Untitled Preset" : name
        }
    }

    private var sizeSelection: Binding<PresetSizeSelection> {
        Binding {
            switch preset.sizeRule {
            case .original:
                .original
            case .preset(let editorPreset):
                PresetSizeSelection(editorPreset: editorPreset)
            case .maxWidth:
                .maxWidth
            }
        } set: { selection in
            preset.sizeRule = selection.sizeRule(currentMaxWidth: maxWidth.wrappedValue)
        }
    }

    private var maxWidth: Binding<Int> {
        Binding {
            if case .maxWidth(let width) = preset.sizeRule {
                return width
            }
            return 960
        } set: { width in
            preset.sizeRule = .maxWidth(max(1, width))
        }
    }

    private var frameRateSelection: Binding<Int> {
        Binding {
            preset.frameRate?.framesPerSecond ?? 0
        } set: { frameRate in
            preset.frameRate = frameRate == 0 ? nil : try? FrameRate(frameRate)
        }
    }

    private var frameRateChoices: [Int] {
        var choices = [0, 12, 24, 30, 60]
        if let current = preset.frameRate?.framesPerSecond,
            !choices.contains(current)
        {
            choices.append(current)
        }

        return [0] + choices.filter { $0 != 0 }.sorted()
    }

    private var destinationSelection: Binding<PresetDestinationSelection> {
        Binding {
            preset.destination == .clipboard ? .clipboard : .recordingsDirectory
        } set: { destination in
            switch destination {
            case .recordingsDirectory:
                preset.destination = .recordingsDirectory
            case .clipboard:
                preset.destination = .clipboard
                preset.postAction = .copyToClipboard
            }
        }
    }

    private var postActionSelection: Binding<ExportPresetPostAction> {
        Binding {
            preset.destination == .clipboard ? .copyToClipboard : preset.postAction
        } set: { action in
            guard preset.destination != .clipboard else {
                return
            }
            preset.postAction = action
        }
    }
}
