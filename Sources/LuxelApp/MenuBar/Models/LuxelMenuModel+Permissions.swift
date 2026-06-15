import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshPermissions() async {
        screenRecordingStatus = await permissionClient.status(for: .screenRecording)
        microphoneStatus = await permissionClient.status(for: .microphone)
        cameraStatus = await permissionClient.status(for: .camera)
    }

    func permissionActionTitle(for permission: SystemPermission) -> String {
        permissionGuidance(for: permission).actionTitle
    }

    func presentPermissionPrompt(for permission: SystemPermission) {
        permissionPrompt = PermissionPrompt(
            permission: permission,
            guidance: permissionGuidance(for: permission)
        )
    }

    func performPermissionAction(_ prompt: PermissionPrompt) async {
        permissionPrompt = nil
        try? await Task.sleep(nanoseconds: 200_000_000)

        switch prompt.guidance.action {
        case .request:
            _ = await permissionClient.request(prompt.permission)
        case .openSettings:
            await permissionClient.openSettings(for: prompt.permission)
        }

        await refreshPermissions()

        if prompt.permission == .screenRecording {
            if screenRecordingStatus != .authorized {
                await permissionClient.openSettings(for: .screenRecording)
            }

            await refreshCaptureTargets()
        } else if prompt.permission == .camera {
            await syncCameraPreviewPanelWithSettings()
        }
    }
    private func permissionGuidance(for permission: SystemPermission) -> PermissionGuidance {
        permissionGuidanceService.guidance(
            for: permission,
            status: permissionStatus(for: permission)
        )
    }

    private func permissionStatus(for permission: SystemPermission) -> PermissionStatus {
        switch permission {
        case .screenRecording:
            screenRecordingStatus
        case .microphone:
            microphoneStatus
        case .camera:
            cameraStatus
        }
    }
}
