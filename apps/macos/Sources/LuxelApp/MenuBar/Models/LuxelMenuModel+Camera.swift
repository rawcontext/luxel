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
        guard cameraStatus == .authorized else {
            closeCameraPreviewOutsideRecording()
            presentPermissionPrompt(for: .camera)
            return
        }

        closeCameraPreviewOutsideRecording()
    }

    func setCameraPreviewStyleFromCropper(_ style: CameraPreviewStyle) async {
        settings.cameraPreviewStyle = style
        saveSettings()
        closeCameraPreviewOutsideRecording()
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

        guard cameraStatus == .authorized else {
            cameraPreviewPanelController.close()
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

    func enableDefaultCameraSource() async {
        if cameraStatus == .unknown {
            await refreshPermissions()
        }

        guard cameraStatus == .authorized else {
            presentPermissionPrompt(for: .camera)
            return
        }

        refreshCameraDevices()
        guard let defaultCamera = cameraDeviceService.defaultCameraDevice(in: cameraDevices) else {
            cameraPreviewPanelController.close()
            return
        }

        settings.cameraDeviceID = defaultCamera.id
        saveSettings()
        closeCameraPreviewOutsideRecording()
    }

    func closeCameraPreviewForFinishedRecording() {
        cameraPreviewPanelController.close()
    }

    func closeCameraPreviewOutsideRecording() {
        switch recordingState {
        case .idle, .failed, .exporting:
            cameraPreviewPanelController.close()
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping:
            break
        }
    }

    func disableCameraSource() {
        settings.cameraDeviceID = nil
        saveSettings()
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
        disableCameraSource()
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
