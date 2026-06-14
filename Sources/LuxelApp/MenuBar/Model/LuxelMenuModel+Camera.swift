import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshCameraDevices() {
        cameraDevices = cameraDeviceService.availableCameraDevices()
    }

    func cropperCameraConfiguration() -> CropperCameraConfiguration {
        CropperCameraConfiguration(
            selectedDeviceID: settings.cameraDeviceID,
            devices: cameraDevices,
            previewStyle: settings.cameraPreviewStyle
        )
    }

    func setCameraDeviceFromCropper(_ cameraDeviceID: String?) async {
        settings.cameraDeviceID = cameraDeviceID
        saveSettings()

        guard cameraDeviceID != nil else {
            cameraPreviewPanelController.close()
            return
        }

        await refreshPermissions()
        if cameraStatus == .notDetermined {
            _ = await permissionClient.request(.camera)
            await refreshPermissions()
        }

        guard cameraStatus == .authorized else {
            await permissionClient.openSettings(for: .camera)
            return
        }

        await syncCameraPreviewPanelWithSettings()
    }

    func setCameraPreviewStyleFromCropper(_ style: CameraPreviewStyle) async {
        settings.cameraPreviewStyle = style
        saveSettings()
        await syncCameraPreviewPanelWithSettings()
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
