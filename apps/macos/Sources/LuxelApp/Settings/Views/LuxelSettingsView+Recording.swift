import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    @ViewBuilder
    var recordingSettingsForm: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsIslandGroup("Capture") {
                settingsToggleRow("Show Cursor", isOn: $model.settings.showCursor)
                    .help("Include the pointer in new recordings.")

                LuxelGlassRowDivider()

                settingsToggleRow("Highlight Clicks", isOn: $model.settings.highlightClicks)
                    .disabled(!model.settings.showCursor)
                    .help("Show a visual ring when clicks happen.")

                LuxelGlassRowDivider()

                settingsToggleRow("Capture Keystrokes", isOn: keystrokeCaptureSelection)
                    .help("Store typed characters and shortcut identities locally with new recordings.")

                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Show Live Keystroke Preview",
                    isOn: $model.settings.keystrokeLivePreviewEnabled
                )
                .disabled(!model.settings.keystrokeOverlayEnabled)
                .help("Show captured keystrokes on screen without including the preview in recordings.")

                LuxelGlassRowDivider()

                recordingFrameRateSettings

                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Match Display Refresh Rate",
                    isOn: matchDisplayFrameRateSelection
                )
                .help("Capture at the display's maximum supported frame rate.")
            }

            VStack(alignment: .leading, spacing: 2) {
                if let recordingFrameRateMessage {
                    Text(recordingFrameRateMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.red)
                } else if model.settings.matchDisplayFrameRate {
                    LuxelGlassSectionFooter(
                        "Frame rate follows the display's supported refresh rate.")
                } else {
                    LuxelGlassSectionFooter("Use a whole number from 1 to 120 FPS.")
                }

                LuxelGlassSectionFooter("Cursor and frame rate apply to new recordings.")
            }
            .padding(.leading, 6)
            .padding(.top, 8)
        }

        SettingsIslandGroup("Audio") {
            settingsToggleRow("Record System Audio", isOn: $model.settings.recordSystemAudio)
                .help("Capture sound playing from your Mac.")

            LuxelGlassRowDivider()

            settingsToggleRow("Record Microphone", isOn: $model.settings.recordAudio)
                .help("Capture audio from the selected microphone.")

            LuxelGlassRowDivider()

            SettingsRow("Microphone") {
                SettingsMenuPicker(
                    selection: audioInputDeviceSelection,
                    options: model.audioInputDevices.map(\.id)
                ) { deviceID in
                    audioInputDeviceLabel(deviceID)
                }
            }
            .disabled(!model.settings.recordAudio)
            .opacity(model.settings.recordAudio ? 1 : 0.45)
            .help("Choose which microphone Luxel records.")

            LuxelGlassRowDivider()

            SettingsRow("Audio-Only Format") {
                SettingsMenuPicker(
                    selection: $model.settings.audioOnlyFormat,
                    options: AudioRecordingFormat.allCases
                ) { format in
                    format.label
                }
            }
            .help("Choose the file format for audio-only recordings.")
        }

        SettingsIslandGroup(
            "Camera",
            footer: cameraSettingsFooter
        ) {
            SettingsRow("Camera") {
                SettingsMenuPicker(
                    selection: $model.settings.cameraDeviceID,
                    options: cameraDeviceOptions
                ) { deviceID in
                    cameraDeviceLabel(deviceID)
                }
            }
            .help("Choose the camera overlay for recordings.")

            LuxelGlassRowDivider()

            SettingsRow("Shape") {
                SettingsMenuPicker(
                    selection: cameraPreviewShapeSelection,
                    options: Array(CameraOverlayShape.allCases)
                ) { shape in
                    shape.settingsLabel
                }
            }
            .disabled(model.settings.cameraDeviceID == nil)
            .opacity(model.settings.cameraDeviceID == nil ? 0.45 : 1)
            .help(model.settings.cameraPreviewStyle.shape.settingsHelp)

            LuxelGlassRowDivider()

            settingsToggleRow(
                LuxelLocalization.string(
                    "cameraOverlay.shape.cutout",
                    defaultValue: "Cutout"
                ),
                isOn: cameraPreviewCutoutSelection
            )
            .disabled(model.settings.cameraDeviceID == nil)
            .help(
                LuxelLocalization.string(
                    "cameraOverlay.shape.cutoutHelp",
                    defaultValue: "Remove the camera background and show only the presenter."
                )
            )

            LuxelGlassRowDivider()

            settingsToggleRow(
                LuxelLocalization.string(
                    "cameraOverlay.background.greenScreen",
                    defaultValue: "Green Screen"
                ),
                isOn: cameraPreviewGreenScreenSelection
            )
            .disabled(model.settings.cameraDeviceID == nil)
            .help(
                LuxelLocalization.string(
                    "cameraOverlay.background.greenScreenHelp",
                    defaultValue: "Remove a green-screen background with chroma key."
                )
            )

            LuxelGlassRowDivider()

            SettingsRow("Size") {
                LuxelGlassSegmentedPicker(
                    selection: cameraPreviewSizeSelection,
                    options: Array(CameraPreviewSize.allCases)
                ) { size in
                    size.settingsLabel
                }
            }
            .disabled(model.settings.cameraDeviceID == nil)
            .opacity(model.settings.cameraDeviceID == nil ? 0.45 : 1)
            .help("Choose the size of the camera overlay.")

            LuxelGlassRowDivider()

            settingsToggleRow("Mirror Preview", isOn: cameraPreviewMirroredSelection)
                .disabled(model.settings.cameraDeviceID == nil)
                .help("Flip the camera preview horizontally.")
        }
    }

    func settingsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(LocalizedStringKey(title), isOn: isOn)
            .toggleStyle(LuxelGlassSwitchToggleStyle())
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    var cameraDeviceOptions: [String?] {
        var options: [String?] = [nil]
        if let unavailableCameraDeviceID {
            options.append(unavailableCameraDeviceID)
        }
        options.append(contentsOf: model.cameraDevices.map(\.id))
        return options
    }

    var cameraSettingsFooter: String {
        switch model.settings.cameraPreviewStyle.backgroundEffect {
        case .portraitCutout:
            return LuxelLocalization.string(
                "cameraOverlay.shape.cutoutHelp",
                defaultValue: "Remove the camera background and show only the presenter."
            )
        case .greenScreen:
            return LuxelLocalization.string(
                "cameraOverlay.background.greenScreenHelp",
                defaultValue: "Remove a green-screen background with chroma key."
            )
        case .none:
            return "Camera controls are available after you choose a camera."
        }
    }

    func cameraDeviceLabel(_ deviceID: String?) -> String {
        guard let deviceID else {
            return "Off"
        }

        guard let device = model.cameraDevices.first(where: { $0.id == deviceID }) else {
            return "Unavailable Camera"
        }

        return device.settingsLabel
    }

    func audioInputDeviceLabel(_ deviceID: String) -> String {
        model.audioInputDevices.first { $0.id == deviceID }?.name ?? deviceID
    }

}
