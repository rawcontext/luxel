import LuxelCore
import SwiftUI

extension LuxelMenu {
    var microphoneFooterPicker: some View {
        Menu {
            ForEach(model.audioInputDevices) { device in
                microphoneFooterDeviceButton(device)
            }
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

    private func microphoneFooterDeviceButton(_ device: AudioInputDeviceOption) -> some View {
        Button {
            model.settings.audioInputDeviceID = device.id
            model.settings.audioInputDeviceName = device.name
            model.saveSettings()
        } label: {
            if selectedAudioInputDeviceID == device.id {
                Label(device.name, systemImage: "checkmark")
            } else {
                Text(device.name)
            }
        }
        .help("Use \(device.name) as the microphone input.")
    }

    private var microphoneFooterPickerAccessibilityValue: String {
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
