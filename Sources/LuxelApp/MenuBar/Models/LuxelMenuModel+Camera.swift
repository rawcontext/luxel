import AppKit
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
            snapRect: cameraPreviewSnapRect,
            showsHoverControls: canShowCameraPreviewHoverControls,
            onPlacementChange: { [weak self] displayID, placement in
                self?.saveCameraPreviewPlacement(displayID: displayID, placement: placement)
            },
            onClose: { [weak self] in
                self?.disableCameraPreviewFromPanel()
            }
        )
    }

    func presentCameraPreviewForRecording(_ request: RecordingRequest) async {
        guard let camera = request.camera,
              camera.isEnabled,
              let cameraDeviceID = camera.deviceID else {
            cameraPreviewPanelController.close()
            return
        }

        if cameraStatus == .unknown {
            await refreshPermissions()
        }

        if cameraStatus == .notDetermined {
            _ = await permissionClient.request(.camera)
            await refreshPermissions()
        }

        guard cameraStatus == .authorized else {
            cameraPreviewPanelController.close()
            presentPermissionPrompt(for: .camera)
            return
        }

        cameraPreviewPanelController.present(
            deviceID: cameraDeviceID,
            style: camera.previewStyle,
            placements: settings.cameraPreviewPlacements,
            snapRect: cameraPreviewSnapRect(for: request.target),
            showsHoverControls: false,
            onPlacementChange: { [weak self] displayID, placement in
                self?.saveCameraPreviewPlacement(displayID: displayID, placement: placement)
            },
            onClose: { [weak self] in
                self?.disableCameraPreviewFromPanel()
            }
        )
    }

    func closeCameraPreviewForFinishedRecording() {
        cameraPreviewPanelController.close()
    }

    func syncCameraPreviewHoverControls() {
        setCameraPreviewHoverControlsEnabled(canShowCameraPreviewHoverControls)
    }

    func setCameraPreviewHoverControlsEnabled(_ isEnabled: Bool) {
        cameraPreviewPanelController.setHoverControlsEnabled(isEnabled)
    }

    func syncCameraPreviewSnapArea() {
        cameraPreviewPanelController.setSnapRect(cameraPreviewSnapRect)
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
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping:
            false
        }
    }

    private var cameraPreviewSnapRect: NSRect? {
        guard let selectedCaptureTarget else {
            return nil
        }

        return cameraPreviewSnapRect(for: selectedCaptureTarget.target)
    }

    private func cameraPreviewSnapRect(for target: CaptureTarget) -> NSRect? {
        return CaptureTargetScreenRectResolver.rect(
            for: target,
            availableTargets: captureTargets
        )
    }
}
