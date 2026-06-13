import AVKit
import LuxelCore
import SwiftUI

public struct LuxelEditorView: View {
    @Bindable var model: LuxelEditorModel

    public init(model: LuxelEditorModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 0) {
            preview

            Divider()

            controls
                .frame(width: 340)
                .background(.thinMaterial)
        }
        .frame(minWidth: 900, minHeight: 560)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.togglePlayback()
                } label: {
                    Label("Play", systemImage: "playpause")
                }
                .disabled(!model.hasSource)

                Button {
                    model.startExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canExport)

                if model.canCancelExport {
                    Button {
                        model.cancelExport()
                    } label: {
                        Label("Cancel Export", systemImage: "xmark.circle")
                    }
                    .help("Cancel Export")
                }

                if let exportedURL = model.exportedURL {
                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            model.saveExportedFileAs()
                        } label: {
                            Label("Save As", systemImage: "tray.and.arrow.down")
                        }
                        .help("Save a Copy")

                        Button {
                            model.openExportedFile()
                        } label: {
                            Label("Open", systemImage: "arrow.up.forward.app")
                        }
                        .help("Open Export")

                        Button {
                            model.openExportedFileWithApplication()
                        } label: {
                            Label("Open With", systemImage: "square.grid.3x3")
                        }
                        .help("Open With")

                        Button {
                            model.copyExportedFile()
                        } label: {
                            Label("Copy File", systemImage: "doc.on.clipboard")
                        }
                        .help("Copy File")

                        ShareLink(item: exportedURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .help("Share Export")
                    }
                    .labelStyle(.iconOnly)
                }
            }
        }
    }

    private var preview: some View {
        ZStack {
            Rectangle()
                .fill(.black)

            if model.hasSource {
                VideoPlayer(player: model.player)
                    .background(.black)
            } else {
                ContentUnavailableView("No Recording", systemImage: "film")
                    .foregroundStyle(.secondary)
            }

            if case .loading = model.status {
                ProgressView()
                    .controlSize(.large)
            }
        }
        .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                exportControls
                if model.showsExportProgressPanel {
                    exportProgressPanel
                }
                timelineControls
                outputControls
                statusControls
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Luxel")
                .font(.headline)
            Text(model.sourceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var exportControls: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Export")

                Picker("Format", selection: formatSelection) {
                    ForEach(LuxelEditorModel.supportedFormats, id: \.self) { format in
                        Text(format.prettyName).tag(format)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Include Audio", isOn: includeAudioSelection)
                    .disabled(!model.canIncludeAudio)

                Toggle("Crop to Fill", isOn: $model.shouldCrop)

                Button {
                    model.startExport()
                } label: {
                    Label(model.isExporting ? "Exporting" : "Export", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
            }
        }
    }

    private var exportProgressPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: model.exportPanelSystemImage)
                        .foregroundStyle(exportPanelTint)
                        .frame(width: 18)

                    Text(model.exportPanelTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer(minLength: 8)
                }

                Text(model.exportPanelMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if model.isExporting || model.exportProgress != nil {
                    ProgressView(value: model.exportProgressValue)
                        .progressViewStyle(.linear)
                }

                ControlGroup {
                    if model.canCancelExport {
                        Button {
                            model.cancelExport()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .help("Cancel Export")
                    }

                    if model.exportedURL != nil {
                        Button {
                            model.revealExportedFile()
                        } label: {
                            Label("Reveal", systemImage: "magnifyingglass")
                        }
                        .help("Reveal in Finder")

                        Button {
                            model.copyExportedFile()
                        } label: {
                            Label("Copy File", systemImage: "doc.on.clipboard")
                        }
                        .help("Copy File")
                    }

                    if model.canRetryExport {
                        Button {
                            model.retryExport()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .help("Export Again")
                    }
                }
                .labelStyle(.iconOnly)
            }
        }
    }

    private var timelineControls: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Timeline")

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Start", value: model.formatTime(model.trimStart))
                    Slider(value: trimStartSelection, in: 0...max(model.duration, model.minimumTrimDuration))
                }

                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("End", value: model.formatTime(model.trimEnd))
                    Slider(value: trimEndSelection, in: model.minimumTrimDuration...max(model.duration, model.minimumTrimDuration))
                }
            }
        }
    }

    private var outputControls: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Output")

                Picker("Size", selection: sizePresetSelection) {
                    Text("Custom").tag(EditorSizePreset?.none)
                    ForEach(LuxelEditorModel.sizePresets, id: \.self) { preset in
                        Text(preset.label).tag(EditorSizePreset?.some(preset))
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Width") {
                    Stepper(value: outputWidthSelection, in: 1...8192, step: 2) {
                        Text("\(model.outputWidth) px")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Height") {
                    Stepper(value: outputHeightSelection, in: 1...8192, step: 2) {
                        Text("\(model.outputHeight) px")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Frame Rate") {
                    Stepper(value: frameRateSelection, in: 1...model.maximumFrameRate) {
                        Text("\(model.frameRate) fps")
                            .monospacedDigit()
                    }
                }

                LabeledContent("Folder") {
                    Button {
                        model.chooseOutputDirectory()
                    } label: {
                        Label {
                            Text(model.outputDirectorySummary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                    .help(model.outputDirectory.path)
                }
            }
        }
    }

    private var statusControls: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(statusTint)
                .lineLimit(2)

            Spacer(minLength: 8)

            if model.exportedURL != nil {
                Button {
                    model.revealExportedFile()
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Reveal in Finder")

                Button {
                    model.copyExportedFilePath()
                } label: {
                    Label("Copy Path", systemImage: "doc.text")
                }
                .labelStyle(.iconOnly)
                .help("Copy File Path")
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusTint: Color {
        if case .failed = model.status {
            return .red
        }

        return .secondary
    }

    private var exportPanelTint: Color {
        switch model.status {
        case .exported, .saved:
            .green
        case .failed:
            .red
        case .canceled:
            .secondary
        default:
            .accentColor
        }
    }

    private var formatSelection: Binding<ExportFormat> {
        Binding {
            model.format
        } set: { format in
            model.setFormat(format)
        }
    }

    private var includeAudioSelection: Binding<Bool> {
        Binding {
            model.includesAudio
        } set: { includesAudio in
            model.setIncludesAudio(includesAudio)
        }
    }

    private var trimStartSelection: Binding<Double> {
        Binding {
            model.trimStart
        } set: { value in
            model.setTrimStart(value)
        }
    }

    private var trimEndSelection: Binding<Double> {
        Binding {
            model.trimEnd
        } set: { value in
            model.setTrimEnd(value)
        }
    }

    private var sizePresetSelection: Binding<EditorSizePreset?> {
        Binding {
            model.sizePreset
        } set: { preset in
            model.setSizePreset(preset)
        }
    }

    private var outputWidthSelection: Binding<Int> {
        Binding {
            model.outputWidth
        } set: { value in
            model.setOutputWidth(value)
        }
    }

    private var outputHeightSelection: Binding<Int> {
        Binding {
            model.outputHeight
        } set: { value in
            model.setOutputHeight(value)
        }
    }

    private var frameRateSelection: Binding<Int> {
        Binding {
            model.frameRate
        } set: { value in
            model.setFrameRate(value)
        }
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}
