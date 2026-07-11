import AppKit
import LuxelCore
import SwiftUI

extension LuxelEditorView {
    var header: some View {
        LuxelGlassIsland(cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                if let source = model.source {
                    editableFilenameField(source)

                    LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 8) {
                        metadataField("Length", model.formatTime(source.duration))
                        if source.hasVideo {
                            metadataField(
                                "Dimensions", "\(source.pixelSize.width)x\(source.pixelSize.height)")
                        } else {
                            metadataField("Type", "Audio")
                        }
                        metadataField("Audio", source.hasAudio ? "Yes" : "No")

                        if source.hasVideo, source.hasAlpha {
                            metadataField("Alpha", "Yes")
                        }
                    }
                } else {
                    Text("No recording loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var metadataColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96), alignment: .leading),
            GridItem(.flexible(minimum: 96), alignment: .leading)
        ]
    }

    func editableFilenameField(_ source: SourceMedia) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Filename")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if isEditingFileName {
                TextField("Filename", text: $editableFileName)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .focused($isFileNameFocused)
                    .onSubmit {
                        commitFileNameEdit(source)
                    }
                    .onExitCommand {
                        cancelFileNameEdit(source)
                    }
                    .help("Edit the recording filename.")
            } else {
                Button {
                    beginFileNameEdit(source)
                } label: {
                    Text(source.fileURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename recording")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            syncEditableFileName(with: source)
        }
        .onChange(of: source.fileURL) { _, _ in
            syncEditableFileName(with: source)
        }
        .onChange(of: isFileNameFocused) { _, isFocused in
            if isEditingFileName, !isFocused {
                commitFileNameEdit(source)
            }
        }
    }

    func metadataField(
        _ label: String,
        _ value: String,
        lineLimit: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func beginFileNameEdit(_ source: SourceMedia) {
        editableFileName = source.fileURL.lastPathComponent
        isEditingFileName = true
        isFileNameFocused = true
    }

    func cancelFileNameEdit(_ source: SourceMedia) {
        isEditingFileName = false
        syncEditableFileName(with: source)
        isFileNameFocused = false
    }

    func commitFileNameEdit(_ source: SourceMedia) {
        guard isEditingFileName else {
            return
        }

        model.renameSourceFile(to: editableFileName)
        isEditingFileName = false
        syncEditableFileName(with: model.source ?? source)
        isFileNameFocused = false
    }

    func syncEditableFileName(with source: SourceMedia) {
        guard !isEditingFileName else {
            return
        }

        editableFileName = source.fileURL.lastPathComponent
    }

    var exportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            exportActionButtons

            if model.showsSpeakerCard {
                EditorSpeakersCard(model: model)
            }

            editorDisclosureCard("Format") {
                VStack(alignment: .leading, spacing: 12) {
                    formatMenu
                        .frame(maxWidth: .infinity, alignment: .trailing)

                    if model.canChooseQuality {
                        controlRow("Quality") {
                            qualityMenu
                        }
                    }

                    if model.showsGIFOptions {
                        LuxelGlassRowDivider()
                        gifControls
                    }

                    LuxelGlassRowDivider()

                    audioExportControls
                }
            }
        }
        .task(id: model.exportEstimateTaskID) {
            await model.refreshExportEstimate()
        }
    }

    var formatMenu: some View {
        Menu {
            ForEach(model.supportedFormats, id: \.self) { format in
                Toggle(isOn: formatSelectionBinding(format)) {
                    Text(formatMenuTitle(for: format))
                }
            }
        } label: {
            LuxelGlassMenuLabel(
                model.selectedFormatSummary,
                systemImage: model.hasAudioOnlySource ? "waveform" : "video"
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Choose the export file format.")
    }

    func formatMenuTitle(for format: ExportFormat) -> String {
        let estimate = model.exportEstimateSummary(for: format) ?? "—"
        return "\(format.prettyName)  \(estimate)"
    }

    var qualityMenu: some View {
        Menu {
            ForEach(model.availableQualities, id: \.self) { quality in
                Button {
                    qualitySelection.wrappedValue = quality
                } label: {
                    if model.quality == quality {
                        Label(quality.label, systemImage: "checkmark")
                    } else {
                        Text(quality.label)
                    }
                }
            }
        } label: {
            LuxelGlassMenuLabel(model.quality.label)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Quality")
        .help("Choose the export quality and file size.")
    }

    var studioVoiceAccessibilityHint: LocalizedStringKey {
        """
        Runs locally, is intended for speech, and is applied only during export. \
        Music and sound effects may change.
        """
    }

    var audioExportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include Audio", isOn: includeAudioSelection)
                .toggleStyle(LuxelGlassCheckboxToggleStyle())
                .disabled(!model.canToggleAudioInclusion)
                .help("Include the source audio in the export.")

            if model.includesAudio {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Level")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.55))

                        Spacer()

                        Text(model.audioVolumePercentSummary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Slider(
                        value: audioVolumeSelection,
                        in: 0...2
                    )
                    .controlSize(.small)
                    .disabled(!model.canAdjustAudioMix)
                    .help("Adjust the exported audio volume.")

                    Toggle("Normalize Audio", isOn: normalizeAudioSelection)
                        .toggleStyle(LuxelGlassCheckboxToggleStyle())
                        .disabled(!model.canAdjustAudioMix)
                        .help("Raise or lower audio to a safe peak level.")

                    Toggle("Studio Voice", isOn: studioVoiceSelection)
                        .toggleStyle(LuxelGlassCheckboxToggleStyle())
                        .disabled(!model.canUseStudioVoice)
                        .help("Reduce background noise and improve spoken audio during export.")
                        .accessibilityHint(studioVoiceAccessibilityHint)
                }
            }
        }
    }

    var exportActionButtons: some View {
        HStack(spacing: 8) {
            saveOriginalButton
            exportButton
        }
    }

    var saveOriginalButton: some View {
        Button {
            model.saveOriginal()
        } label: {
            Text("Save Original")
        }
        .buttonStyle(LuxelGlassPillButtonStyle())
        .disabled(!model.canSaveOriginal)
        .help("Save an unchanged copy of the recording.")
    }

    var exportButton: some View {
        Button {
            model.startExport()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))

                Text(model.isExporting ? "Exporting" : "Export")
            }
        }
        .buttonStyle(LuxelGlassPillButtonStyle(isProminent: true))
        .disabled(!model.canExport)
        .help("Export with the selected settings.")
    }

    var gifControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlRow("Loop") {
                editorMenuPicker(
                    selection: gifLoopModeSelection,
                    options: Array(EditorGIFLoopModeKind.allCases)
                ) { kind in
                    kind.label
                }
                .accessibilityLabel("Loop")
                .help("Choose how the GIF repeats.")
            }

            if model.gifLoopModeKind == .count {
                controlRow("Loop Count") {
                    Stepper(value: gifLoopCountSelection, in: 1...100) {
                        Text("\(model.gifLoopCount)x")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .help("Set how many times the GIF repeats.")
                }
            }

            controlRow("Dithering") {
                editorMenuPicker(
                    selection: gifDitheringSelection,
                    options: Array(GIFDitheringMode.allCases)
                ) { mode in
                    gifDitheringLabel(mode)
                }
                .accessibilityLabel("Dithering")
                .help("Control how GIF colors are blended.")
            }
        }
    }

    func editorMenuPicker<Option: Hashable>(
        selection: Binding<Option>,
        options: [Option],
        optionLabel: @escaping (Option) -> String
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if option == selection.wrappedValue {
                        Label(optionLabel(option), systemImage: "checkmark")
                    } else {
                        Text(optionLabel(option))
                    }
                }
            }
        } label: {
            LuxelGlassMenuLabel(optionLabel(selection.wrappedValue))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }

}
