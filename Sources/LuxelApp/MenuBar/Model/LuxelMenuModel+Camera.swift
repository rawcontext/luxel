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
            style: settings.cameraPreviewStyle,
            placements: settings.cameraPreviewPlacements,
            showsHoverControls: canShowCameraPreviewHoverControls,
            onPlacementChange: { [weak self] displayID, placement in
                self?.saveCameraPreviewPlacement(displayID: displayID, placement: placement)
            },
            onClose: { [weak self] in
                self?.disableCameraPreviewFromPanel()
            }
        )
    }

    func syncCameraPreviewHoverControls() {
        setCameraPreviewHoverControlsEnabled(canShowCameraPreviewHoverControls)
    }

    func setCameraPreviewHoverControlsEnabled(_ isEnabled: Bool) {
        cameraPreviewPanelController.setHoverControlsEnabled(isEnabled)
    }

    private func disableCameraPreviewFromPanel() {
        settings.cameraDeviceID = nil
        saveSettings()
        cameraPreviewPanelController.close()
    }

    private func saveCameraPreviewPlacement(
        displayID: DisplayID,
        placement: CameraPreviewPlacement
    ) {
        guard settings.cameraPreviewPlacements[displayID] != placement else {
            return
        }

        settings.cameraPreviewPlacements[displayID] = placement
        saveSettings()
    }

    private var canShowCameraPreviewHoverControls: Bool {
        switch recordingState {
        case .idle, .failed, .exporting:
            true
        case .starting, .recording, .pausing, .paused, .resuming, .stopping:
            false
        }
    }
}
