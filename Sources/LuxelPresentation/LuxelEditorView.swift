import AVKit
import AppKit
import LuxelCore
import SwiftUI

public struct LuxelEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissWindow) private var dismissWindow
    @Bindable var model: LuxelEditorModel
    @State private var isConfirmingDiscard = false
    @State private var editorWindow: NSWindow?

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
        .background(EditorWindowReader(window: $editorWindow))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.undoEditorChange()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canUndoEditorChange)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo Editor Change")

                Button {
                    model.redoEditorChange()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!model.canRedoEditorChange)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo Editor Change")

                Divider()

                Button {
                    model.togglePlayback()
                } label: {
                    Label("Play", systemImage: "playpause")
                }
                .disabled(!model.hasSource)

                Button {
                    model.copyCurrentFrame()
                } label: {
                    Label("Copy Frame", systemImage: "doc.on.clipboard")
                }
                .disabled(!model.canGrabFrame)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .help("Copy Frame")

                Button {
                    model.saveCurrentFrameAs()
                } label: {
                    Label("Save Frame As", systemImage: "photo.badge.arrow.down")
                }
                .disabled(!model.canGrabFrame)
                .help("Save Frame As")

                Button {
                    model.startExport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.canExport)

                Button {
                    requestDiscard()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .disabled(!model.canDiscard)
                .keyboardShortcut("d", modifiers: .command)
                .help("Discard Recording")

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
        .confirmationDialog(
            "Discard Recording?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Recording", role: .destructive) {
                discardRecording()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move this recording to the Trash.")
        }
        .dialogSuppressionToggle(
            Text("Don't ask me again"),
            isSuppressed: suppressDiscardConfirmation
        )
        .focusedSceneValue(\.luxelEditorCommandContext, editorCommandContext)
    }

    private var editorCommandContext: LuxelEditorCommandContext {
        LuxelEditorCommandContext(
            canUndo: model.canUndoEditorChange,
            canRedo: model.canRedoEditorChange,
            canDiscard: model.canDiscard,
            canGrabFrame: model.canGrabFrame,
            undo: {
                model.undoEditorChange()
            },
            redo: {
                model.redoEditorChange()
            },
            discard: {
                requestDiscard()
            },
            copyFrame: {
                model.copyCurrentFrame()
            },
            saveFrameAs: {
                model.saveCurrentFrameAs()
            }
        )
    }

    private func requestDiscard() {
        if model.confirmDiscard {
            isConfirmingDiscard = true
        } else {
            discardRecording()
        }
    }

    private func discardRecording() {
        if model.discardRecording() {
            editorWindow?.close()
            dismissWindow(id: LuxelEditorScene.id)
            dismiss()
        }
    }

    private var suppressDiscardConfirmation: Binding<Bool> {
        Binding {
            !model.confirmDiscard
        } set: { isSuppressed in
            model.setConfirmDiscard(!isSuppressed)
        }
    }

    private var preview: some View {
        ZStack {
            if model.usesAlphaPreviewBackground {
                CheckerboardBackground()
            } else {
                Rectangle()
                    .fill(.black)
            }

            if model.hasSource {
                LuxelPlayerView(
                    player: model.player,
                    usesAlphaBackground: model.usesAlphaPreviewBackground
                )
                .background(model.usesAlphaPreviewBackground ? .clear : .black)
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
        .contextMenu {
            Button("Copy Frame") {
                model.copyCurrentFrame()
            }
            .disabled(!model.canGrabFrame)

            Button("Save Frame As...") {
                model.saveCurrentFrameAs()
            }
            .disabled(!model.canGrabFrame)
        }
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

                Menu {
                    ForEach(model.supportedFormats, id: \.self) { format in
                        Toggle(isOn: formatSelectionBinding(format)) {
                            Text(format.prettyName)
                        }
                    }
                } label: {
                    Label(model.selectedFormatSummary, systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.button)

                if model.canChooseQuality {
                    Picker("Quality", selection: qualitySelection) {
                        ForEach(model.availableQualities, id: \.self) { quality in
                            Text(quality.label).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if model.showsGIFOptions {
                    gifControls
                }

                Toggle("Include Audio", isOn: includeAudioSelection)
                    .disabled(!model.canIncludeAudio)

                if model.canIncludeAudio {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Audio Level", value: model.audioVolumePercentSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: audioVolumeSelection,
                            in: 0...2
                        )
                        .disabled(!model.canAdjustAudioMix)

                        Toggle("Normalize Audio", isOn: normalizeAudioSelection)
                            .disabled(!model.canAdjustAudioMix)
                    }
                }

                Toggle("Crop to Fill", isOn: shouldCropSelection)

                if let exportEstimateSummary = model.exportEstimateSummary {
                    LabeledContent("Estimated Size", value: exportEstimateSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    model.startExport()
                } label: {
                    Label(model.isExporting ? "Exporting" : "Export", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)

                Button {
                    model.saveOriginal()
                } label: {
                    Label("Save Original", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canSaveOriginal)
            }
        }
        .task(id: model.exportEstimateTaskID) {
            await model.refreshExportEstimate()
        }
    }

    private var gifControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Loop", selection: gifLoopModeSelection) {
                ForEach(EditorGIFLoopModeKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.menu)

            if model.gifLoopModeKind == .count {
                LabeledContent("Loop Count") {
                    Stepper(value: gifLoopCountSelection, in: 1...100) {
                        Text("\(model.gifLoopCount)x")
                            .monospacedDigit()
                    }
                }
            }

            Picker("Dithering", selection: gifDitheringSelection) {
                ForEach(GIFDitheringMode.allCases, id: \.self) { mode in
                    Text(gifDitheringLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)
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

                if !model.exportJobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.exportJobs) { job in
                            exportJobRow(job)
                        }
                    }
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

                LabeledContent("Output Duration", value: model.outputDurationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                LabeledContent("Speed") {
                    HStack(spacing: 8) {
                        TextField("Speed", value: playbackSpeedSelection, format: .number.precision(.fractionLength(2)))
                            .frame(width: 58)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()

                        Text("x")
                            .foregroundStyle(.secondary)

                        Menu {
                            ForEach(LuxelEditorModel.playbackSpeedDetents, id: \.self) { speed in
                                Button(speedPresetLabel(speed)) {
                                    model.setPlaybackSpeed(speed)
                                }
                            }
                        } label: {
                            Label("Speed Presets", systemImage: "speedometer")
                        }
                        .labelStyle(.iconOnly)
                        .help("Speed Presets")
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
        case .exported, .exportedBatch, .saved:
            .green
        case .failed:
            .red
        case .canceled:
            .secondary
        default:
            .accentColor
        }
    }

    private func exportJobRow(_ job: ExportJobSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: exportJobSystemImage(job))
                .foregroundStyle(exportJobTint(job))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(job.format.prettyName)
                        .font(.caption)
                        .fontWeight(.semibold)

                    Spacer(minLength: 8)

                    Text(job.statusSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                ProgressView(value: job.progressValue)
                    .progressViewStyle(.linear)
            }

            if job.fileURL != nil {
                Button {
                    model.revealExportJob(job)
                } label: {
                    Label("Reveal", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Reveal in Finder")
            }
        }
    }

    private func exportJobSystemImage(_ job: ExportJobSnapshot) -> String {
        switch job.progress?.phase {
        case .preparing, .exporting:
            "arrow.triangle.2.circlepath"
        case .completed:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
        case .none:
            "clock"
        }
    }

    private func exportJobTint(_ job: ExportJobSnapshot) -> Color {
        switch job.progress?.phase {
        case .completed:
            .green
        case .canceled:
            .secondary
        default:
            .accentColor
        }
    }

    private func formatSelectionBinding(_ format: ExportFormat) -> Binding<Bool> {
        Binding {
            model.selectedFormats.contains(format)
        } set: { isSelected in
            model.setFormatSelection(format, isSelected: isSelected)
        }
    }

    private var includeAudioSelection: Binding<Bool> {
        Binding {
            model.includesAudio
        } set: { includesAudio in
            model.setIncludesAudio(includesAudio)
        }
    }

    private var audioVolumeSelection: Binding<Double> {
        Binding {
            model.audioVolume
        } set: { volume in
            model.setAudioVolume(volume)
        }
    }

    private var normalizeAudioSelection: Binding<Bool> {
        Binding {
            model.normalizeAudio
        } set: { normalizeAudio in
            model.setNormalizeAudio(normalizeAudio)
        }
    }

    private var qualitySelection: Binding<ExportQuality> {
        Binding {
            model.quality
        } set: { quality in
            model.setQuality(quality)
        }
    }

    private var gifLoopModeSelection: Binding<EditorGIFLoopModeKind> {
        Binding {
            model.gifLoopModeKind
        } set: { kind in
            model.setGIFLoopModeKind(kind)
        }
    }

    private var gifLoopCountSelection: Binding<Int> {
        Binding {
            model.gifLoopCount
        } set: { count in
            model.setGIFLoopCount(count)
        }
    }

    private var gifDitheringSelection: Binding<GIFDitheringMode> {
        Binding {
            model.gifDithering
        } set: { mode in
            model.setGIFDithering(mode)
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

    private var playbackSpeedSelection: Binding<Double> {
        Binding {
            model.playbackSpeedValue
        } set: { value in
            model.setPlaybackSpeed(value)
        }
    }

    private var shouldCropSelection: Binding<Bool> {
        Binding {
            model.shouldCrop
        } set: { shouldCrop in
            model.setShouldCrop(shouldCrop)
        }
    }

    private func speedPresetLabel(_ speed: Double) -> String {
        if speed == speed.rounded() {
            return "\(Int(speed))x"
        }

        return String(format: "%.2fx", speed)
            .replacingOccurrences(of: #"\.?0+x$"#, with: "x", options: .regularExpression)
    }

    private func gifDitheringLabel(_ mode: GIFDitheringMode) -> String {
        switch mode {
        case .auto:
            "Auto"
        case .none:
            "None"
        case .ordered:
            "Ordered"
        case .diffusion:
            "Diffusion"
        }
    }
}

private struct EditorWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowReaderView {
        WindowReaderView()
    }

    func updateNSView(_ nsView: WindowReaderView, context: Context) {
        nsView.onWindowChange = { window in
            self.window = window
        }
        window = nsView.window
    }
}

private final class WindowReaderView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

private struct LuxelPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let usesAlphaBackground: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = player
        updateBackground(for: view)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }

        updateBackground(for: nsView)
    }

    private func updateBackground(for view: AVPlayerView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = usesAlphaBackground
            ? NSColor.clear.cgColor
            : NSColor.black.cgColor
    }
}

private struct CheckerboardBackground: View {
    private let squareSize: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let columns = Int((size.width / squareSize).rounded(.up))
            let rows = Int((size.height / squareSize).rounded(.up))

            for row in 0...rows {
                for column in 0...columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(.white.opacity(0.16)))
                }
            }
        }
        .background(Color.black)
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
