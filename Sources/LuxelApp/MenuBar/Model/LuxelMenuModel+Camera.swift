import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshCameraDevices() {
        cameraDevices = cameraDeviceService.availableCameraDevices()
    }

    func syncCameraPreviewPanelWithSettings() async {
        guard let cameraDeviceID = settings.cameraDeviceID else {
            cameraPreviewPanelController.close()
            return
        }

        if cameraStatus == .unknown {
            await refreshPermissions()
        }

        guard cameraStatus == .authorized else {
            cameraPreviewPanelController.close()
            presentPermissionPrompt(for: .camera)
            return
        }

        cameraPreviewPanelController.present(
            deviceID: cameraDeviceID,
            style: settings.cameraPreviewStyle
        )
    }
}
