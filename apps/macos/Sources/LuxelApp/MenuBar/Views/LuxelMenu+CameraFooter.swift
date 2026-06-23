import LuxelCore
import SwiftUI

extension LuxelMenu {
    var cameraFooterPicker: some View {
        Menu {
            cameraFooterMenuItems
        } label: {
            Image(systemName: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(
                    width: LuxelCameraFooterPickerLayout.buttonWidth,
                    height: LuxelCameraFooterPickerLayout.buttonHeight
                )
                .luxelMenuControlBackground(
                    cornerRadius: LuxelCameraFooterPickerLayout.buttonCornerRadius
                )
        }
        .buttonStyle(.plain)
        .frame(height: LuxelCameraFooterPickerLayout.buttonHeight)
        .help("Choose camera")
        .accessibilityLabel("Choose Camera")
        .accessibilityValue(cameraFooterPickerAccessibilityValue)
    }

    @ViewBuilder
    private var cameraFooterMenuItems: some View {
        cameraFooterDeviceButton(title: "Off", deviceID: nil)

        if let unavailableCameraDeviceID {
            cameraFooterDeviceButton(title: "Unavailable Camera", deviceID: unavailableCameraDeviceID)
        }

        if model.cameraDevices.isEmpty {
            Divider()
            Text("No cameras found")
        } else {
            Divider()

            ForEach(model.cameraDevices) { device in
                cameraFooterDeviceButton(title: device.settingsLabel, deviceID: device.id)
            }
        }
    }

    private func cameraFooterDeviceButton(title: String, deviceID: String?) -> some View {
        Button {
            Task {
                await model.setCameraDevice(deviceID)
            }
        } label: {
            if model.settings.cameraDeviceID == deviceID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .help(deviceID == nil ? "Turn off the camera overlay." : "Use \(title) as the camera overlay.")
    }

    private var cameraFooterPickerAccessibilityValue: String {
        model.cropperCameraConfiguration().selectedDevice?.name ?? "Camera Off"
    }

    private var unavailableCameraDeviceID: String? {
        guard let cameraDeviceID = model.settings.cameraDeviceID,
              !model.cameraDevices.contains(where: { $0.id == cameraDeviceID })
        else {
            return nil
        }

        return cameraDeviceID
    }
}

private enum LuxelCameraFooterPickerLayout {
    static let buttonWidth: CGFloat = 30
    static let buttonHeight: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 11
}
