import Foundation
import LuxelCore
import SwiftUI

struct ExportPresetSettingsSection: View {
    @Binding var settings: AppSettings
    @State private var selectedPresetID: UUID?

    var body: some View {
        Group {
            Section("Quick Recording") {
                Picker("Quick Preset", selection: $settings.quickExportPresetID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(settings.exportPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)
                .help("Choose the preset used by quick recording.")

                Toggle("Remember Last Capture", isOn: $settings.rememberLastCapture)
                    .help("Reuse the last capture target for quick recording.")
            }

            Section("Presets") {
                Picker("Edit Preset", selection: editPresetSelection) {
                    ForEach(settings.exportPresets) { preset in
                        Text(preset.name).tag(Optional(preset.id))
                    }
                }
                .pickerStyle(.menu)
                .disabled(settings.exportPresets.isEmpty)
                .help("Choose which export preset to edit.")

                HStack {
                    Button {
                        addPreset()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .help("Create a new export preset.")

                    Button {
                        duplicateSelectedPreset()
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .disabled(currentSelectedPresetID == nil)
                    .help("Copy the selected export preset.")

                    Button(role: .destructive) {
                        deleteSelectedPreset()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(currentSelectedPresetID == nil)
                    .help("Delete the selected export preset.")
                }
                .buttonStyle(.bordered)

                if let selectedPresetBinding {
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

    private var editPresetSelection: Binding<UUID?> {
        Binding {
            currentSelectedPresetID
        } set: { presetID in
            selectedPresetID = presetID
        }
    }

    private var currentSelectedPresetID: UUID? {
        if let selectedPresetID,
           settings.exportPresets.contains(where: { $0.id == selectedPresetID }) {
            return selectedPresetID
        }

        if let quickExportPresetID = settings.quickExportPresetID,
           settings.exportPresets.contains(where: { $0.id == quickExportPresetID }) {
            return quickExportPresetID
        }

        return settings.exportPresets.first?.id
    }

    private var selectedPresetBinding: Binding<ExportPreset>? {
        guard let selectedPresetID = currentSelectedPresetID,
              let index = settings.exportPresets.firstIndex(where: { $0.id == selectedPresetID })
        else {
            return nil
        }

        return Binding {
            settings.exportPresets[index]
        } set: { preset in
            settings.exportPresets[index] = preset
        }
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
        TextField("Name", text: name)
            .help("Name this export preset.")

        Picker("Format", selection: $preset.format) {
            ForEach(ExportFormat.appleNativeV1Formats, id: \.self) { format in
                Text(format.prettyName).tag(format)
            }
        }
        .pickerStyle(.menu)
        .help("Choose the export file format.")

        Picker("Size", selection: sizeSelection) {
            ForEach(PresetSizeSelection.allCases) { selection in
                Text(selection.label).tag(selection)
            }
        }
        .pickerStyle(.menu)
        .help("Choose how much to resize exported video.")

        if case .maxWidth = preset.sizeRule {
            Stepper(value: maxWidth, in: 1...10_000, step: 10) {
                Text("Max Width \(maxWidth.wrappedValue) px")
            }
            .help("Set the maximum exported width in pixels.")
        }

        Picker("Frame Rate", selection: frameRateSelection) {
            ForEach(frameRateChoices, id: \.self) { frameRate in
                Text(frameRate == 0 ? "Source" : "\(frameRate) FPS").tag(frameRate)
            }
        }
        .pickerStyle(.menu)
        .help("Choose the exported video frame rate.")

        Picker("Destination", selection: destinationSelection) {
            ForEach(PresetDestinationSelection.allCases) { destination in
                Text(destination.label).tag(destination)
            }
        }
        .pickerStyle(.menu)
        .help("Choose where the exported result goes.")

        Picker("After Export", selection: postActionSelection) {
            ForEach(ExportPresetPostAction.allCases, id: \.self) { action in
                Text(action.label).tag(action)
            }
        }
        .pickerStyle(.menu)
        .disabled(preset.destination == .clipboard)
        .help("Choose what Luxel does after exporting.")
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
           !choices.contains(current) {
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

private enum PresetSizeSelection: String, CaseIterable, Identifiable {
    case original
    case percent75
    case percent50
    case percent33
    case percent25
    case percent20
    case percent10
    case maxWidth

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .original:
            "Original"
        case .percent75:
            "75%"
        case .percent50:
            "50%"
        case .percent33:
            "33%"
        case .percent25:
            "25%"
        case .percent20:
            "20%"
        case .percent10:
            "10%"
        case .maxWidth:
            "Max Width"
        }
    }

    init(editorPreset: EditorSizePreset) {
        switch editorPreset {
        case .original:
            self = .original
        case .percent75:
            self = .percent75
        case .percent50:
            self = .percent50
        case .percent33:
            self = .percent33
        case .percent25:
            self = .percent25
        case .percent20:
            self = .percent20
        case .percent10:
            self = .percent10
        }
    }

    func sizeRule(currentMaxWidth: Int) -> ExportPresetSizeRule {
        switch self {
        case .original:
            .original
        case .percent75:
            .preset(.percent75)
        case .percent50:
            .preset(.percent50)
        case .percent33:
            .preset(.percent33)
        case .percent25:
            .preset(.percent25)
        case .percent20:
            .preset(.percent20)
        case .percent10:
            .preset(.percent10)
        case .maxWidth:
            .maxWidth(currentMaxWidth)
        }
    }
}

private enum PresetDestinationSelection: String, CaseIterable, Identifiable {
    case recordingsDirectory
    case clipboard

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .recordingsDirectory:
            "Recordings Folder"
        case .clipboard:
            "Clipboard"
        }
    }
}

extension ExportPresetPostAction {
    fileprivate var label: String {
        switch self {
        case .none:
            "None"
        case .revealInFinder:
            "Reveal in Finder"
        case .copyToClipboard:
            "Copy to Clipboard"
        case .notifyWithThumbnail:
            "Notify with Thumbnail"
        }
    }
}
