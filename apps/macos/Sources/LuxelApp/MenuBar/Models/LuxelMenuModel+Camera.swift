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

    func setCameraDevice(_ cameraDeviceID: String?) async {
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

    func setCameraDeviceFromCropper(_ cameraDeviceID: String?) async {
        await setCameraDevice(cameraDeviceID)
    }

    func setCameraPreviewStyleFromCropper(_ style: CameraPreviewStyle) async {
        settings.cameraPreviewStyle = style
        saveSettings()
        closeCameraPreviewOutsideRecording()
    }

    func presentCameraPreviewForRecording(_ request: RecordingRequest) async {
        guard let camera = request.camera,
              camera.isEnabled,
              let cameraDeviceID = camera.deviceID
        else {
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
            onCutoutFailure: { [weak self] in
                self?.recordingNoticeMessage = Self.cameraCutoutUnavailableNotice
            },
            onClose: { [weak self] in
                self?.disableCameraPreviewFromPanel()
            }
        )
    }

    func preparingCameraCutoutIfNeeded(
        for request: RecordingRequest
    ) async -> (request: RecordingRequest, noticeMessage: String?) {
        guard let camera = request.camera,
              camera.isEnabled,
              camera.previewStyle.shape.usesPortraitMatting
        else {
            return (request, nil)
        }

        do {
            try await cameraPreviewPanelController.prepareCutout()
            return (request, nil)
        } catch {
            let fallbackStyle = CameraPreviewStyle(
                shape: .circle,
                size: camera.previewStyle.size,
                isMirrored: camera.previewStyle.isMirrored
            )
            return (
                request.replacingCamera(camera.replacingPreviewStyle(fallbackStyle)),
                Self.cameraCutoutUnavailableNotice
            )
        }
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

    func closeCameraPreviewForRecordingStop() async {
        await cameraPreviewPanelController.closeAndWaitForSessionStop()
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

    private static var cameraCutoutUnavailableNotice: String {
        LuxelLocalization.string(
            "cameraOverlay.cutout.unavailable",
            defaultValue: "Camera background removal was unavailable. Showing Squircle instead."
        )
    }
}
