import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelCropperView {
    var cropperOverlayControls: some View {
        ZStack(alignment: .bottom) {
            if shouldShowNotificationReminder {
                VStack {
                    notificationReminderPanel
                        .padding(.top, 28)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            bottomToolbar
                .padding(.bottom, Self.toolbarBottomPadding + toolbarBottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    var shouldShowNotificationReminder: Bool {
        showsNotificationReminder && model.canRecordSelection
    }

    var bottomToolbar: some View {
        HStack(spacing: 6) {
            fullDisplayButton
            sizePresetMenu
            aspectRatioMenu

            toolbarDivider

            recordAudioToggle
            cameraMenu
            countdownMenu
            stopAfterMenu

            toolbarDivider

            cancelButton
            primaryActionButton
        }
        .padding(8)
        .luxelMenuIslandBackground(cornerRadius: 26)
        .background(
            Color.black.opacity(0.32),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .fixedSize()
        .appKitCursor(.arrow)
    }

    var toolbarDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 2)
    }

    func toolbarCircleLabel(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDisabled ? .tertiary : isActive ? .primary : .secondary)
            .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
            .background {
                toolbarControlBackground(in: Circle(), isActive: isActive, isDisabled: isDisabled)
            }
            .contentShape(Circle())
    }

    func toolbarPillLabel(_ title: String, isActive: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .lineLimit(1)

            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .frame(height: Self.toolbarPillHeight)
        .background {
            toolbarControlBackground(in: Capsule(style: .continuous), isActive: isActive)
        }
        .contentShape(Capsule(style: .continuous))
    }

    func toolbarControlBackground<S: InsettableShape>(
        in shape: S,
        isActive: Bool = false,
        isDisabled: Bool = false
    ) -> some View {
        shape
            .fill(.white.opacity(isDisabled ? 0.04 : isActive ? 0.16 : 0.08))
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(isDisabled ? 0.05 : isActive ? 0.2 : 0.1), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
    }

    var fullDisplayButton: some View {
        Button {
            model.selectFullDisplay()
        } label: {
            toolbarCircleLabel("Full Display", systemImage: "display")
        }
        .buttonStyle(.plain)
        .help("Select the full current display.")
    }

    var countdownMenu: some View {
        Menu {
            countdownButton(title: "Off", duration: nil)

            Divider()

            ForEach(CountdownPreset.all) { preset in
                countdownButton(title: preset.title, duration: preset.duration)
            }
        } label: {
            toolbarCircleLabel(
                "Countdown",
                systemImage: "clock",
                isActive: model.countdownDuration != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Countdown")
        .accessibilityValue(model.countdownSummary)
        .help("Delay recording after pressing Record. Current: \(model.countdownSummary).")
    }

    var stopAfterMenu: some View {
        Menu {
            stopAfterButton(title: "Off", duration: nil)

            Divider()

            ForEach(StopAfterPreset.all) { preset in
                stopAfterButton(title: preset.title, duration: preset.duration)
            }

            Divider()

            TextField("h:mm:ss", text: customStopAfterText)
                .frame(width: 84)
                .help("Enter a custom automatic stop duration.")

            Button {
                applyCustomStopAfterDuration()
            } label: {
                Label("Set Custom", systemImage: "timer")
            }
            .help("Use the custom automatic stop duration.")
        } label: {
            toolbarCircleLabel(
                "Stop After",
                systemImage: "square",
                isActive: model.stopAfterDuration != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Stop After")
        .accessibilityValue(model.stopAfterSummary)
        .help("Stop recording automatically. Current: \(model.stopAfterSummary).")
    }

    var aspectRatioMenu: some View {
        Menu {
            ForEach(CaptureAspectRatioPreset.allCases, id: \.self) { preset in
                Button {
                    model.setAspectRatioPreset(preset)
                } label: {
                    if model.customAspectRatio == nil, model.aspectRatioPreset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
                .help(
                    LuxelLocalization.format(
                        "cropper.aspectRatioPreset.help",
                        defaultValue: "Use the %@ aspect ratio for the selected area.",
                        preset.title)
                )
            }

            Divider()

            TextField("Custom W", text: customAspectRatioWidthText)
                .frame(width: 76)
                .help("Custom aspect ratio width.")
            TextField("Custom H", text: customAspectRatioHeightText)
                .frame(width: 76)
                .help("Custom aspect ratio height.")

            Button {
                applyCustomAspectRatio()
            } label: {
                if let customAspectRatio = model.customAspectRatio {
                    Label("\(customAspectRatio.width):\(customAspectRatio.height)", systemImage: "checkmark")
                } else {
                    Label("Apply Custom", systemImage: "aspectratio")
                }
            }
            .help("Apply the custom aspect ratio values.")
        } label: {
            toolbarPillLabel(model.aspectRatioSummary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Aspect Ratio")
        .accessibilityValue(model.aspectRatioSummary)
        .help(
            LuxelLocalization.format(
                "cropper.aspectRatio.currentHelp",
                defaultValue: "Constrain the selected area. Current: %@.",
                model.aspectRatioSummary)
        )
    }

    var sizePresetMenu: some View {
        Menu {
            ForEach(model.sizePresets) { preset in
                Button {
                    model.applySizePreset(preset)
                } label: {
                    Text(preset.name)
                }
                .help(
                    LuxelLocalization.format(
                        "cropper.sizePreset.applyHelp",
                        defaultValue: "Apply the %@ size preset.",
                        preset.name)
                )
            }
        } label: {
            toolbarPillLabel("Size")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .help("Apply a saved size preset to the selected area.")
    }

}
