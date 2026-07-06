import LuxelCore
import SwiftUI

extension LuxelMenu {
    var cameraFooterPicker: some View {
        Menu {
            cameraFooterMenuItems
        } label: {
            Image(systemName: "chevron.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(
                    width: LuxelCameraFooterPickerLayout.buttonWidth,
                    height: LuxelCameraFooterPickerLayout.buttonHeight
                )
                .contentShape(Rectangle())
                .luxelIslandCellHighlight()
        }
        .buttonStyle(.plain)
        .frame(height: LuxelCameraFooterPickerLayout.buttonHeight)
        .help("Choose camera")
        .accessibilityLabel("Choose Camera")
        .accessibilityValue(cameraFooterPickerAccessibilityValue)
    }

    @ViewBuilder
    private var cameraFooterMenuItems: some View {
        Picker("Camera", selection: cameraFooterSelection) {
            Text("Off").tag(Optional<String>.none)

            if let unavailableCameraDeviceID {
                Text("Unavailable Camera").tag(Optional(unavailableCameraDeviceID))
            }

            ForEach(model.cameraDevices) { device in
                Text(device.settingsLabel).tag(Optional(device.id))
            }
        }
        .pickerStyle(.inline)

        if model.cameraDevices.isEmpty {
            Divider()
            Text("No cameras found")
        }
    }

    private var cameraFooterSelection: Binding<String?> {
        Binding {
            model.settings.cameraDeviceID
        } set: { deviceID in
            Task {
                await model.setCameraDevice(deviceID)
            }
        }
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
    static let buttonHeight: CGFloat = 36
}
