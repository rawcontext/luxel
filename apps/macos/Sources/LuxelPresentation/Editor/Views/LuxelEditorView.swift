import AppKit
import LuxelCore
import SwiftUI

public struct LuxelEditorView: View {
    @Bindable var model: LuxelEditorModel
    @State private var editableFileName = ""
    @State private var isEditingFileName = false
    @FocusState private var isFileNameFocused: Bool

    public init(model: LuxelEditorModel) {
        self.model = model
    }
}

extension LuxelEditorView {
    public var body: some View {
        HStack(spacing: 12) {
            preview

            controls
                .frame(width: 280)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(minWidth: 900, minHeight: 560)
        .tint(.white)
        .preferredColorScheme(.dark)
        .navigationTitle(model.source?.fileURL.lastPathComponent ?? "Luxel")
        .background {
            LuxelGlassWindowBackground()
                .overlay(LuxelGlassWindowChromeConfigurator())
        }
        .onDisappear {
            model.pausePlayback()
        }
    }

    @ViewBuilder
    private var preview: some View {
        if model.hasAudioOnlySource {
            audioStage
        } else {
            videoStage
        }
    }

    private var audioStage: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                recordingNavigationButtons

                Spacer(minLength: 0)
            }

            AudioTranscriptPreview(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if !showsTranscriptContent {
                        ContentUnavailableView("Audio Recording", systemImage: "waveform")
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }

                    if case .loading = model.status {
                        ProgressView()
                            .controlSize(.large)
                    }
                }

            if model.hasSource {
                EditorPlaybackCapsule(model: model)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoStage: some View {
        // Mirrors audioStage: navigation lives in a row above the stage so the
        // arrows do not move when flipping between audio and video recordings.
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                recordingNavigationButtons

                Spacer(minLength: 0)

                transcriptPreviewControls
            }

            videoFrame
        }
        .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var videoFrame: some View {
        ZStack {
            if model.usesAlphaPreviewBackground {
                CheckerboardBackground()
            } else {
                Rectangle()
                    .fill(.black)
            }

            if model.hasVideoSource {
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

            AudioTranscriptPreview(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .bottom) {
            if model.hasSource {
                EditorPlaybackCapsule(model: model)
                    .padding(.horizontal, 48)
                    .padding(.bottom, 14)
            }
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

    private var showsTranscriptContent: Bool {
        model.shouldShowSpeechRecognitionPrompt
            || model.shouldShowTranscriptProgress
            || model.shouldShowTranscriptFailure
            || model.visibleTranscript != nil
    }

    private var recordingNavigationButtons: some View {
        HStack(spacing: 6) {
            recordingNavigationButton(
                title: "Back",
                systemImage: "chevron.left",
                isEnabled: model.canNavigateToNewerRecording
            ) {
                await model.navigateToNewerRecording()
            }
            .help("Open newer recording")

            recordingNavigationButton(
                title: "Forward",
                systemImage: "chevron.right",
                isEnabled: model.canNavigateToOlderRecording
            ) {
                await model.navigateToOlderRecording()
            }
            .help("Open older recording")
        }
    }

    @ViewBuilder
    private var transcriptPreviewControls: some View {
        if model.canShowVideoTranscriptToggle {
            Button {
                model.toggleTranscriptPanel()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 11, weight: .medium))

                    Text(transcriptPreviewButtonTitle)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule(style: .continuous)
                        .fill(EditorStageChromeStyle.fill)
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(transcriptPreviewButtonHelp)
        }
    }

    private var transcriptPreviewButtonTitle: String {
        if model.isTranscriptExtractionActive {
            return "Transcribing"
        }

        return "Transcript"
    }

    private var transcriptPreviewButtonHelp: String {
        model.isTranscriptPanelVisible ? "Hide transcript" : "Show transcript"
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.3))
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(EditorStageChromeStyle.fill)
                        .overlay {
                            Circle()
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .contentShape(Circle())
                .accessibilityLabel(title)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
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
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
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

    private var metadataColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 96), alignment: .leading),
            GridItem(.flexible(minimum: 96), alignment: .leading)
        ]
    }

    private func editableFilenameField(_ source: SourceMedia) -> some View {
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

    private func metadataField(
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

    private func beginFileNameEdit(_ source: SourceMedia) {
        editableFileName = source.fileURL.lastPathComponent
        isEditingFileName = true
        isFileNameFocused = true
    }

    private func cancelFileNameEdit(_ source: SourceMedia) {
        isEditingFileName = false
        syncEditableFileName(with: source)
        isFileNameFocused = false
    }

    private func commitFileNameEdit(_ source: SourceMedia) {
        guard isEditingFileName else {
            return
        }

        model.renameSourceFile(to: editableFileName)
        isEditingFileName = false
        syncEditableFileName(with: model.source ?? source)
        isFileNameFocused = false
    }

    private func syncEditableFileName(with source: SourceMedia) {
        guard !isEditingFileName else {
            return
        }

        editableFileName = source.fileURL.lastPathComponent
    }

    private var exportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            exportActionButtons

            if model.showsSpeakerCard {
                EditorSpeakersCard(model: model)
            }

            editorDisclosureCard("Format") {
                VStack(alignment: .leading, spacing: 12) {
                    controlRow("Format") {
                        formatMenu
                    }

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

    private var formatMenu: some View {
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
    }

    private func formatMenuTitle(for format: ExportFormat) -> String {
        let estimate = model.exportEstimateSummary(for: format) ?? "—"
        return "\(format.prettyName)  \(estimate)"
    }

    private var qualityMenu: some View {
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
    }

    private var audioExportControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Include Audio", isOn: includeAudioSelection)
                .toggleStyle(LuxelGlassCheckboxToggleStyle())
                .disabled(!model.canToggleAudioInclusion)

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

                    Toggle("Normalize Audio", isOn: normalizeAudioSelection)
                        .toggleStyle(LuxelGlassCheckboxToggleStyle())
                        .disabled(!model.canAdjustAudioMix)
                }
            }
        }
    }

    private var exportActionButtons: some View {
        HStack(spacing: 8) {
            saveOriginalButton
            exportButton
        }
    }

    private var saveOriginalButton: some View {
        Button {
            model.saveOriginal()
        } label: {
            Text("Save Original")
        }
        .buttonStyle(LuxelGlassPillButtonStyle())
        .disabled(!model.canSaveOriginal)
    }

    private var exportButton: some View {
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
    }

    private var gifControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlRow("Loop") {
                editorMenuPicker(
                    selection: gifLoopModeSelection,
                    options: Array(EditorGIFLoopModeKind.allCases)
                ) { kind in
                    kind.label
                }
                .accessibilityLabel("Loop")
            }

            if model.gifLoopModeKind == .count {
                controlRow("Loop Count") {
                    Stepper(value: gifLoopCountSelection, in: 1...100) {
                        Text("\(model.gifLoopCount)x")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                    }
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
            }
        }
    }

    private func editorMenuPicker<Option: Hashable>(
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

    private var timelineControls: some View {
        editorDisclosureCard("Timeline") {
            VStack(alignment: .leading, spacing: 9) {
                timelineSliderRow(
                    "Start",
                    value: model.formatTime(model.trimStart),
                    slider: Slider(
                        value: trimStartSelection, in: 0...max(model.duration, model.minimumTrimDuration))
                )

                timelineSliderRow(
                    "End",
                    value: model.formatTime(model.trimEnd),
                    slider: Slider(
                        value: trimEndSelection,
                        in: model.minimumTrimDuration...max(model.duration, model.minimumTrimDuration)
                    )
                )

                HStack {
                    Text("Output Duration")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))

                    Spacer()

                    Text(model.outputDurationSummary)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    private var outputControls: some View {
        editorDisclosureCard("Output") {
            VStack(alignment: .leading, spacing: 12) {
                if model.hasVideoSource {
                    controlRow("Size") {
                        editorMenuPicker(
                            selection: sizePresetSelection,
                            options: [EditorSizePreset?.none]
                                + LuxelEditorModel.sizePresets.map(EditorSizePreset?.some)
                        ) { preset in
                            preset?.label ?? "Custom"
                        }
                        .accessibilityLabel("Size")
                    }

                    controlRow("Fit") {
                        Toggle("Crop to Fill", isOn: shouldCropSelection)
                            .toggleStyle(LuxelGlassCheckboxToggleStyle())
                    }

                    LuxelGlassRowDivider()

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

                    LuxelGlassRowDivider()
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

                LuxelGlassRowDivider()

                controlRow("Folder") {
                    Button {
                        model.chooseOutputDirectory()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .medium))

                            Text(model.outputDirectorySummary)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            Capsule(style: .continuous)
                                .fill(LuxelGlassTheme.controlFill)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            LinearGradient(
                                                colors: [LuxelGlassTheme.controlHighlight, .clear],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ),
                                            lineWidth: 1
                                        )
                                }
                        }
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(model.outputDirectory.path)
                }
            }
        }
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
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 8)

            content()
        }
    }

    private func timelineSliderRow<SliderContent: View>(
        _ label: String,
        value: String,
        slider: SliderContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Spacer()

                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
            }

            slider
                .controlSize(.small)
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
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .luxelGlassFieldBackground()
        } onIncrement: {
            value.wrappedValue = min(
                range.upperBound, value.wrappedValue + currentStep(step, shiftedStep))
        } onDecrement: {
            value.wrappedValue = max(
                range.lowerBound, value.wrappedValue - currentStep(step, shiftedStep))
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
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 42)
                .multilineTextAlignment(.trailing)
                .luxelGlassFieldBackground()
        } onIncrement: {
            value.wrappedValue = roundedSpeed(
                min(range.upperBound, value.wrappedValue + currentStep(step, shiftedStep)))
        } onDecrement: {
            value.wrappedValue = roundedSpeed(
                max(range.lowerBound, value.wrappedValue - currentStep(step, shiftedStep)))
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
}
