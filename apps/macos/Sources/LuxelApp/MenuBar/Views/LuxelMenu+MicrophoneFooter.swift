import LuxelCore
import SwiftUI

extension LuxelMenu {
    var microphoneFooterPicker: some View {
        Menu {
            Picker("Microphone", selection: microphoneFooterSelection) {
                Text("Off").tag(Optional<String>.none)

                ForEach(model.audioInputDevices) { device in
                    Text(device.name)
                        .tag(Optional(device.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: LuxelMicrophoneFooterPickerLayout.buttonWidth,
                    height: LuxelMicrophoneFooterPickerLayout.buttonHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: LuxelMicrophoneFooterPickerLayout.buttonHeight)
        .help("Choose microphone")
        .accessibilityLabel("Choose Microphone")
        .accessibilityValue(microphoneFooterPickerAccessibilityValue)
    }

    private var microphoneFooterSelection: Binding<String?> {
        Binding {
            model.settings.recordAudio ? selectedAudioInputDeviceID : nil
        } set: { selectedID in
            guard let selectedID else {
                model.settings.recordAudio = false
                model.saveSettings()
                return
            }

            if let device = model.audioInputDevices.first(where: { $0.id == selectedID }) {
                model.settings.recordAudio = true
                model.settings.audioInputDeviceID = device.id
                model.settings.audioInputDeviceName = device.name
                model.saveSettings()
            }
        }
    }

    private var microphoneFooterPickerAccessibilityValue: String {
        guard model.settings.recordAudio else {
            return LuxelLocalization.string(
                "permissions.microphone.off.title",
                defaultValue: "Microphone is off"
            )
        }

        return model.audioInputDevices.first { $0.id == selectedAudioInputDeviceID }?.name
            ?? model.settings.audioInputDeviceName
            ?? AudioInputDeviceOption.systemDefault.name
    }

    private var selectedAudioInputDeviceID: String {
        model.settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
    }
}

private enum LuxelMicrophoneFooterPickerLayout {
    static let buttonWidth: CGFloat = 36
    static let buttonHeight: CGFloat = 34
}
