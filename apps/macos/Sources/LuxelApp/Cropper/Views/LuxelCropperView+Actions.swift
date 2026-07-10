import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelCropperView {
    @ViewBuilder
    var cameraMenu: some View {
        let cameraConfiguration = effectiveCameraConfiguration

        Menu {
            cameraDeviceButton(title: "Off", deviceID: nil)

            if !cameraConfiguration.devices.isEmpty {
                Divider()

                ForEach(cameraConfiguration.devices) { device in
                    cameraDeviceButton(title: device.settingsLabel, deviceID: device.id)
                }
            }

            if cameraConfiguration.selectedDeviceID != nil {
                Divider()

                Menu {
                    ForEach(CameraOverlayShape.allCases, id: \.self) { shape in
                        Button {
                            updateCameraPreviewShape(shape)
                        } label: {
                            if cameraConfiguration.previewStyle.shape == shape {
                                Label(shape.settingsLabel, systemImage: "checkmark")
                            } else {
                                Text(shape.settingsLabel)
                            }
                        }
                        .help(shape.settingsHelp)
                    }
                } label: {
                    Label("Shape", systemImage: "circle")
                }
                .help("Set the camera overlay shape.")

                Button {
                    toggleCameraBackgroundEffect(.portraitCutout)
                } label: {
                    let title = LuxelLocalization.string(
                        "cameraOverlay.shape.cutout",
                        defaultValue: "Cutout"
                    )
                    if cameraConfiguration.previewStyle.backgroundEffect == .portraitCutout {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
                .help(
                    LuxelLocalization.string(
                        "cameraOverlay.shape.cutoutHelp",
                        defaultValue: "Remove the camera background and show only the presenter."
                    )
                )

                Button {
                    toggleCameraBackgroundEffect(.greenScreen)
                } label: {
                    let title = LuxelLocalization.string(
                        "cameraOverlay.background.greenScreen",
                        defaultValue: "Green Screen"
                    )
                    if cameraConfiguration.previewStyle.backgroundEffect == .greenScreen {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
                .help(
                    LuxelLocalization.string(
                        "cameraOverlay.background.greenScreenHelp",
                        defaultValue: "Remove a green-screen background with chroma key."
                    )
                )

                Menu {
                    ForEach(CameraPreviewSize.allCases, id: \.self) { size in
                        Button {
                            updateCameraPreviewSize(size)
                        } label: {
                            if cameraConfiguration.previewStyle.size == size {
                                Label(size.settingsLabel, systemImage: "checkmark")
                            } else {
                                Text(size.settingsLabel)
                            }
                        }
                        .help(
                            LuxelLocalization.format(
                                "cameraOverlay.size.optionHelp",
                                defaultValue: "Set the camera overlay size to %@.",
                                size.settingsLabel)
                        )
                    }
                } label: {
                    Label("Size", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Set the camera overlay size.")

                Button {
                    updateCameraPreviewMirror(!cameraConfiguration.previewStyle.isMirrored)
                } label: {
                    if cameraConfiguration.previewStyle.isMirrored {
                        Label("Mirror", systemImage: "checkmark")
                    } else {
                        Text("Mirror")
                    }
                }
                .help("Flip the camera preview horizontally.")
            }
        } label: {
            toolbarCircleLabel(
                cameraToolbarText,
                systemImage: cameraMenuSystemImage,
                isActive: cameraConfiguration.selectedDeviceID != nil
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .accessibilityLabel("Camera")
        .accessibilityValue(cameraToolbarText)
        .help(cameraMenuHelp)
    }

    var recordAudioToggle: some View {
        Button {
            recordAudio.wrappedValue.toggle()
        } label: {
            toolbarCircleLabel(
                microphoneToolbarText,
                systemImage: model.recordsAudio ? "mic.fill" : "mic.slash",
                isActive: model.recordsAudio,
                isDisabled: !model.canToggleRecordAudio
            )
        }
        .buttonStyle(.plain)
        .frame(width: Self.toolbarCircleSide, height: Self.toolbarCircleSide)
        .disabled(!model.canToggleRecordAudio)
        .accessibilityLabel("Microphone")
        .accessibilityValue(microphoneToolbarText)
        .help(recordAudioHelp)
    }

    var notificationReminderPanel: some View {
        GlassPanel {
            HStack(spacing: 10) {
                Image(systemName: "moon")
                    .foregroundStyle(.secondary)

                Text("Tip: enable a Focus to silence notifications.")
                    .font(.callout)
                    .foregroundStyle(.primary)

                Button {
                    openFocusSettings()
                } label: {
                    Label("Focus Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Focus settings to silence notifications while recording.")

                Button {
                    onNotificationReminderDismiss()
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Hide the notification reminder.")
            }
        }
        .fixedSize()
        .appKitCursor(.arrow)
    }

    @ViewBuilder
    var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            toolbarCircleLabel("Cancel", systemImage: "xmark")
        }
        .buttonStyle(.plain)
        .help("Close area selection without recording or capturing.")
    }

    func recordPillLabel(isDisabled: Bool) -> some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 13, height: 13)

            Text(model.primaryActionTitle)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .opacity(isDisabled ? 0.55 : 1)
        .padding(.leading, 13)
        .padding(.trailing, 16)
        .frame(height: Self.toolbarPillHeight)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            LuxelMenuIslandStyle.recordRedTop,
                            LuxelMenuIslandStyle.recordRedBottom
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .saturation(isDisabled ? 0.35 : 1)
                .opacity(isDisabled ? 0.5 : 1)
                .shadow(
                    color: LuxelMenuIslandStyle.recordGlow.opacity(isDisabled ? 0 : 0.35),
                    radius: 11,
                    y: 4
                )
        }
        .contentShape(Capsule(style: .continuous))
    }

    @ViewBuilder
    var primaryActionButton: some View {
        Button {
            commitPrimarySelection()
        } label: {
            recordPillLabel(isDisabled: !model.canRecordSelection)
        }
        .buttonStyle(.plain)
        .disabled(!model.canRecordSelection)
        .accessibilityLabel(model.primaryActionTitle)
        .help(primaryActionHelp)
        .contextMenu {
            Button {
                commitSelection()
            } label: {
                Label("Record", systemImage: "record.circle")
            }
            .help("Record the selected area.")

            if !quickRecordingConfiguration.presets.isEmpty {
                Menu {
                    ForEach(quickRecordingConfiguration.presets) { preset in
                        Button {
                            commitSelection(quickPresetID: preset.id)
                        } label: {
                            Label(preset.name, systemImage: quickPresetSystemImage(for: preset))
                        }
                        .help(
                            LuxelLocalization.format(
                                "cropper.quickPreset.recordHelp",
                                defaultValue: "Record with the %@ quick export preset.",
                                preset.name)
                        )
                    }
                } label: {
                    Label("Quick Record", systemImage: "bolt.circle")
                }
                .help("Record with a quick export preset.")
            }
        }
    }
}
