import AppKit
import LuxelCore
import SwiftUI

public struct LuxelEditorView: View {
    @Bindable var model: LuxelEditorModel

    public init(model: LuxelEditorModel) {
        self.model = model
    }
}

extension LuxelEditorView {
    public var body: some View {
        HStack(spacing: 0) {
            preview

            Divider()

            controls
                .frame(width: 340)
                .background(.thinMaterial)
        }
        .frame(minWidth: 900, minHeight: 560)
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
        .overlay(alignment: .topLeading) {
            recordingNavigationControls
        }
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

    private var recordingNavigationControls: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                recordingNavigationButton(
                    title: "Back",
                    systemImage: "chevron.left",
                    isEnabled: model.canNavigateToOlderRecording
                ) {
                    await model.navigateToOlderRecording()
                }
                .help("Open older recording")

                recordingNavigationButton(
                    title: "Forward",
                    systemImage: "chevron.right",
                    isEnabled: model.canNavigateToNewerRecording
                ) {
                    await model.navigateToNewerRecording()
                }
                .help("Open newer recording")
            }
        }
        .controlSize(.small)
        .padding(12)
    }

    private func recordingNavigationButton(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
        }
        .buttonStyle(.glass)
        .disabled(!isEnabled)
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
                if let sidebarStatusMessage = model.sidebarStatusMessage {
                    statusControls(sidebarStatusMessage)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let source = model.source {
                metadataField("Filename", source.fileURL.lastPathComponent, lineLimit: 2)

                LazyVGrid(columns: metadataColumns, alignment: .leading, spacing: 8) {
                    metadataField("Length", model.formatTime(source.duration))
                    metadataField("Dimensions", "\(source.pixelSize.width)x\(source.pixelSize.height)")
                    metadataField("Audio", source.hasAudio ? "Yes" : "No")

                    if source.hasAlpha {
                        metadataField("Alpha", "Yes")
                    }
                }
            } else {
                Text("No recording loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metadataColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96), alignment: .leading),
            GridItem(.flexible(minimum: 96), alignment: .leading)
        ]
    }

    private func metadataField(
        _ label: String,
        _ value: String,
        lineLimit: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .monospacedDigit()
        }
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            editorCard {
                exportActions
            }

            editorDisclosureCard("Export Format") {
                VStack(alignment: .leading, spacing: 14) {
                    controlRow("Format") {
                        formatMenu
                    }

                    if model.canChooseQuality {
                        qualityPicker
                    }

                    if model.showsGIFOptions {
                        Divider()
                        gifControls
                    }

                    Divider()

                    audioExportControls
                }
            }
        }
        .task(id: model.exportEstimateTaskID) {
            await model.refreshExportEstimate()
        }
    }

    private var formatMenu: some View {
        Menu {
            ForEach(model.supportedFormats, id: \.self) { format in
                Toggle(isOn: formatSelectionBinding(format)) {
                    Text(format.prettyName)
                }
            }
        } label: {
            Label(model.selectedFormatSummary, systemImage: "video")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
    }

    private var qualityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quality")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Picker("Quality", selection: qualitySelection) {
                ForEach(model.availableQualities, id: \.self) { quality in
                    Text(quality.label).tag(quality)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var audioExportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include Audio", isOn: includeAudioSelection)
                .disabled(!model.canIncludeAudio)

            if model.includesAudio {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Level")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(model.audioVolumePercentSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: audioVolumeSelection,
                        in: 0...2
                    )
                    .disabled(!model.canAdjustAudioMix)

                    Toggle("Normalize Audio", isOn: normalizeAudioSelection)
                        .disabled(!model.canAdjustAudioMix)
                }
                .padding(.leading, 2)
            }
        }
    }

    private var exportActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let exportEstimateSummary = model.exportEstimateSummary {
                Text(exportEstimateSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Button {
                    model.saveOriginal()
                } label: {
                    exportActionLabel("Save Original", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(!model.canSaveOriginal)

                Button {
                    model.startExport()
                } label: {
                    exportActionLabel(
                        model.isExporting ? "Exporting" : "Export",
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canExport)
            }
            .controlSize(.large)
        }
    }

    private func exportActionLabel(
        _ title: String,
        systemImage: String
    ) -> some View {
        Label(title, systemImage: systemImage)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
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
                    if showsExportPanelStatusIcon {
                        Image(systemName: model.exportPanelSystemImage)
                            .foregroundStyle(exportPanelTint)
                            .frame(width: 18)
                    }

                    Text(model.exportPanelTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer(minLength: 8)
                }

                Text(model.exportPanelMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if model.exportJobs.count > 1, model.isExporting || model.exportProgress != nil {
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

                exportProgressActions
            }
        }
    }

    @ViewBuilder
    private var exportProgressActions: some View {
        HStack(spacing: 8) {
            if model.canCancelExport {
                Button {
                    model.cancelExport()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .help("Cancel the export in progress.")
            }

            if let exportedURL = model.exportedURL {
                Button {
                    model.openExportedFile()
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .help("Open the exported file.")

                Menu {
                    exportedFileMenuItems(exportedURL: exportedURL)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More exported file actions.")
            }

            if model.canRetryExport {
                Button {
                    model.retryExport()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .help("Run the export again.")
            }
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private func exportedFileMenuItems(exportedURL: URL) -> some View {
        Button {
            model.revealExportedFile()
        } label: {
            Label("Reveal in Finder", systemImage: "magnifyingglass")
        }

        Button {
            model.saveExportedFileAs()
        } label: {
            Label("Save a Copy...", systemImage: "tray.and.arrow.down")
        }

        Button {
            model.openExportedFileWithApplication()
        } label: {
            Label("Open With...", systemImage: "square.grid.3x3")
        }

        Divider()

        Button {
            model.copyExportedFile()
        } label: {
            Label("Copy File", systemImage: "doc.on.clipboard")
        }

        Button {
            model.copyExportedFilePath()
        } label: {
            Label("Copy Path", systemImage: "doc.text")
        }

        ShareLink(item: exportedURL) {
            Label("Share...", systemImage: "square.and.arrow.up")
        }
    }

    private var timelineControls: some View {
        editorDisclosureCard("Timeline") {
            VStack(alignment: .leading, spacing: 12) {
                timelineSliderRow(
                    "Start",
                    value: model.formatTime(model.trimStart),
                    slider: Slider(value: trimStartSelection, in: 0...max(model.duration, model.minimumTrimDuration))
                )

                timelineSliderRow(
                    "End",
                    value: model.formatTime(model.trimEnd),
                    slider: Slider(
                        value: trimEndSelection,
                        in: model.minimumTrimDuration...max(model.duration, model.minimumTrimDuration)
                    )
                )

                LabeledContent("Output Duration", value: model.outputDurationSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var outputControls: some View {
        editorDisclosureCard("Output") {
            VStack(alignment: .leading, spacing: 14) {
                controlRow("Size") {
                    Picker("Size", selection: sizePresetSelection) {
                        Text("Custom").tag(EditorSizePreset?.none)
                        ForEach(LuxelEditorModel.sizePresets, id: \.self) { preset in
                            Text(preset.label).tag(EditorSizePreset?.some(preset))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                controlRow("Fit") {
                    Toggle("Crop to Fill", isOn: shouldCropSelection)
                }

                Divider()

                controlRow("Width") {
                    integerStepperField(
                        "Width",
                        value: outputWidthSelection,
                        range: 1...8192,
                        unitHelp: "Pixels",
                        step: 2,
                        shiftedStep: 100
                    )
                }

                controlRow("Height") {
                    integerStepperField(
                        "Height",
                        value: outputHeightSelection,
                        range: 1...8192,
                        unitHelp: "Pixels",
                        step: 2,
                        shiftedStep: 100
                    )
                }

                controlRow("Frame Rate") {
                    integerStepperField(
                        "Frame Rate",
                        value: frameRateSelection,
                        range: 1...model.maximumFrameRate,
                        unitHelp: "Frames per second",
                        step: 1,
                        shiftedStep: 10
                    )
                }

                controlRow("Speed") {
                    doubleStepperField(
                        "Speed",
                        value: playbackSpeedSelection,
                        range: 0.1...10,
                        unitHelp: "Playback speed multiplier",
                        step: 0.1,
                        shiftedStep: 0.5
                    )
                }

                Divider()

                controlRow("Folder") {
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

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        GlassPanel {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func editorDisclosureCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        EditorDisclosureCard(title, content: content)
    }

    private func controlRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 88, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timelineSliderRow<SliderContent: View>(
        _ label: String,
        value: String,
        slider: SliderContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            slider
        }
    }

    private func statusControls(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(statusTint)
            .lineLimit(2)
        .padding(.horizontal, 4)
    }

    private func integerStepperField(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unitHelp: String,
        step: Int,
        shiftedStep: Int
    ) -> some View {
        Stepper {
            TextField(title, value: value, format: .number)
                .frame(width: 72)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        } onIncrement: {
            value.wrappedValue = min(range.upperBound, value.wrappedValue + currentStep(step, shiftedStep))
        } onDecrement: {
            value.wrappedValue = max(range.lowerBound, value.wrappedValue - currentStep(step, shiftedStep))
        }
        .help(unitHelp)
    }

    private func doubleStepperField(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unitHelp: String,
        step: Double,
        shiftedStep: Double
    ) -> some View {
        Stepper {
            TextField(title, value: value, format: .number.precision(.fractionLength(1)))
                .frame(width: 58)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        } onIncrement: {
            value.wrappedValue = roundedSpeed(min(range.upperBound, value.wrappedValue + currentStep(step, shiftedStep)))
        } onDecrement: {
            value.wrappedValue = roundedSpeed(max(range.lowerBound, value.wrappedValue - currentStep(step, shiftedStep)))
        }
        .help(unitHelp)
    }

    private func currentStep<T>(_ step: T, _ shiftedStep: T) -> T {
        NSEvent.modifierFlags.contains(.shift) ? shiftedStep : step
    }

    private func roundedSpeed(_ value: Double) -> Double {
        (value * 100).rounded() / 100
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
            if showsExportJobStatusIcon(job) {
                Image(systemName: exportJobSystemImage(job))
                    .foregroundStyle(exportJobTint(job))
                    .frame(width: 18)
            }

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

    private var showsExportPanelStatusIcon: Bool {
        model.exportPanelSystemImage != "checkmark.circle"
    }

    private func showsExportJobStatusIcon(_ job: ExportJobSnapshot) -> Bool {
        job.progress?.phase != .completed
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

private struct EditorDisclosureCard<Content: View>: View {
    @State private var isExpanded = false

    private let title: String
    private let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        cardContainer
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardContainer: some View {
        if #available(macOS 26.0, *) {
            cardContent
                .glassEffect(in: .rect(cornerRadius: 8))
        } else {
            cardContent
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    SectionLabel(title)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, isExpanded ? 12 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
