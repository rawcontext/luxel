import AppKit
import LuxelCore
import SwiftUI

extension LuxelEditorView {
    var keystrokeControls: some View {
        editorDisclosureCard("Keystrokes") {
            VStack(alignment: .leading, spacing: 12) {
                controlRow("Show") {
                    Toggle("Show Keystrokes", isOn: keystrokesVisibleSelection)
                        .labelsHidden()
                        .toggleStyle(LuxelGlassCheckboxToggleStyle())
                }

                controlRow("Position") {
                    editorMenuPicker(
                        selection: keystrokeAnchorSelection,
                        options: KeystrokeOverlayAnchor.allCases
                    ) { keystrokeAnchorLabel($0) }
                }

                controlRow("Size") {
                    editorMenuPicker(
                        selection: keystrokeSizeSelection,
                        options: KeystrokeOverlaySize.allCases
                    ) { $0.rawValue.capitalized }
                }

                controlRow("Theme") {
                    editorMenuPicker(
                        selection: keystrokeThemeSelection,
                        options: KeystrokeOverlayTheme.allCases
                    ) { keystrokeThemeLabel($0) }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Display Duration")
                        Spacer()
                        Text("\(keystrokeDurationSelection.wrappedValue, specifier: "%.1f") s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: keystrokeDurationSelection, in: 0.5...5, step: 0.1)
                }

                Button("Remove Keystroke Data", role: .destructive) {
                    model.removeKeystrokeData()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Permanently delete the locally stored keystroke sidecar for this recording.")
            }
        }
    }

    private func keystrokeAnchorLabel(_ anchor: KeystrokeOverlayAnchor) -> String {
        switch anchor {
        case .topLeft: "Top Left"
        case .topCenter: "Top Center"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomCenter: "Bottom Center"
        case .bottomRight: "Bottom Right"
        }
    }

    private func keystrokeThemeLabel(_ theme: KeystrokeOverlayTheme) -> String {
        switch theme {
        case .darkGlass: "Dark Glass"
        case .lightGlass: "Light Glass"
        case .highContrast: "High Contrast"
        }
    }

    var timelineControls: some View {
        editorDisclosureCard("Timeline") {
            VStack(alignment: .leading, spacing: 9) {
                timelineSliderRow(
                    "Start",
                    value: model.formatTime(model.trimStart),
                    slider: Slider(
                        value: trimStartSelection, in: 0...max(model.duration, model.minimumTrimDuration))
                )
                .help("Choose where the exported clip starts.")

                timelineSliderRow(
                    "End",
                    value: model.formatTime(model.trimEnd),
                    slider: Slider(
                        value: trimEndSelection,
                        in: model.minimumTrimDuration...max(model.duration, model.minimumTrimDuration)
                    )
                )
                .help("Choose where the exported clip ends.")

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

    var outputControls: some View {
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
                        .help("Choose how much to resize exported video.")
                    }

                    controlRow("Fit") {
                        Toggle("Crop to Fill", isOn: shouldCropSelection)
                            .toggleStyle(LuxelGlassCheckboxToggleStyle())
                            .help("Crop the video to fill the output dimensions.")
                    }

                    LuxelGlassRowDivider()

                    controlRow("Width") {
                        integerStepperField(
                            "Width",
                            value: outputWidthSelection,
                            range: 1...8192,
                            help: "Set the exported width in pixels.",
                            steps: (normal: 2, shifted: 100)
                        )
                    }

                    controlRow("Height") {
                        integerStepperField(
                            "Height",
                            value: outputHeightSelection,
                            range: 1...8192,
                            help: "Set the exported height in pixels.",
                            steps: (normal: 2, shifted: 100)
                        )
                    }

                    controlRow("Frame Rate") {
                        integerStepperField(
                            "Frame Rate",
                            value: frameRateSelection,
                            range: 1...model.maximumFrameRate,
                            help: "Set the exported frame rate.",
                            steps: (normal: 1, shifted: 10)
                        )
                    }

                    LuxelGlassRowDivider()
                }

                controlRow("Speed") {
                    doubleStepperField(
                        "Speed",
                        value: playbackSpeedSelection,
                        range: 0.1...10,
                        help: "Set the exported playback speed.",
                        steps: (normal: 0.1, shifted: 0.5)
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
                    .help("Choose where to save the exported file.")
                }
            }
        }
    }

    func editorDisclosureCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        EditorDisclosureCard(title, content: content)
    }

    func controlRow<Content: View>(
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

    func timelineSliderRow<SliderContent: View>(
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

    func statusControls(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(statusTint)
            .lineLimit(2)
            .padding(.horizontal, 4)
    }

    func integerStepperField(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        help: LocalizedStringKey,
        steps: (normal: Int, shifted: Int)
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
                range.upperBound, value.wrappedValue + currentStep(steps.normal, steps.shifted))
        } onDecrement: {
            value.wrappedValue = max(
                range.lowerBound, value.wrappedValue - currentStep(steps.normal, steps.shifted))
        }
        .help(help)
    }

    func doubleStepperField(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        help: LocalizedStringKey,
        steps: (normal: Double, shifted: Double)
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
                min(range.upperBound, value.wrappedValue + currentStep(steps.normal, steps.shifted)))
        } onDecrement: {
            value.wrappedValue = roundedSpeed(
                max(range.lowerBound, value.wrappedValue - currentStep(steps.normal, steps.shifted)))
        }
        .help(help)
    }

    func currentStep<T>(_ step: T, _ shiftedStep: T) -> T {
        NSEvent.modifierFlags.contains(.shift) ? shiftedStep : step
    }

    func roundedSpeed(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    var statusTint: Color {
        if case .failed = model.status {
            return .red
        }

        return .secondary
    }
}
