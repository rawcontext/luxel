import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshPermissions() async {
        screenRecordingStatus = await permissionClient.status(for: .screenRecording)
        microphoneStatus = await permissionClient.status(for: .microphone)
        cameraStatus = await permissionClient.status(for: .camera)
        let refreshedInputMonitoringStatus = await permissionClient.status(for: .inputMonitoring)
        if inputMonitoringStatus != .denied || refreshedInputMonitoringStatus == .authorized {
            inputMonitoringStatus = refreshedInputMonitoringStatus
        }
    }

    func presentPermissionPrompt(for permission: SystemPermission) {
        switch permission {
        case .screenRecording:
            presentPermissionPrompt(forSource: .screenPixels)
        case .microphone:
            presentPermissionPrompt(forSource: .microphone)
        case .camera:
            presentPermissionPrompt(forSource: .camera)
        case .inputMonitoring:
            permissionPrompt = PermissionPrompt(
                source: nil,
                permission: permission,
                guidance: permissionGuidance(for: permission)
            )
        }
    }

    func presentPermissionPrompt(forSource source: CapturePermissionSource) {
        permissionPrompt = makePermissionPrompt(forSource: source)
    }

    func makePermissionPrompt(forSource source: CapturePermissionSource) -> PermissionPrompt {
        PermissionPrompt(
            source: source,
            permission: source.systemPermission,
            guidance: permissionGuidance(for: source)
        )
    }

    func performPermissionAction(_ prompt: PermissionPrompt) async {
        permissionPrompt = nil
        await performGuidanceAction(prompt)
        await refreshPermissions()
        await openSettingsAfterDeniedRequest(prompt)
        if prompt.permission == .inputMonitoring, inputMonitoringStatus == .authorized {
            settings.keystrokeOverlayEnabled = true
            saveSettings()
        }
        if let source = prompt.source {
            await refreshCaptureSource(source)
        }
    }

    private func performGuidanceAction(_ prompt: PermissionPrompt) async {
        switch prompt.guidance.action {
        case .request:
            try? await Task.sleep(nanoseconds: 200_000_000)
            if prompt.permission == .inputMonitoring {
                inputMonitoringStatus = await permissionClient.request(.inputMonitoring)
            }
            if permissionStatus(for: prompt.permission) != .authorized {
                await refreshPermissions()
            }
        case .openSettings:
            try? await Task.sleep(nanoseconds: 200_000_000)
            await permissionClient.openSettings(for: prompt.permission)
        case .enableSource:
            if let source = prompt.source {
                enableCaptureSource(source)
            }
        }
    }

    private func openSettingsAfterDeniedRequest(_ prompt: PermissionPrompt) async {
        if prompt.guidance.action == .request,
           permissionStatus(for: prompt.permission) != .authorized {
            await permissionClient.openSettings(for: prompt.permission)
        }
    }

    private func refreshCaptureSource(_ source: CapturePermissionSource) async {
        switch source {
        case .screenPixels:
            await refreshCaptureTargets()
        case .systemAudio:
            if screenRecordingStatus == .authorized {
                settings.recordSystemAudio = true
                saveSettings()
            }

            await refreshCaptureTargets()
        case .microphone:
            if microphoneStatus == .authorized {
                settings.recordAudio = true
                saveSettings()
            }
        case .camera:
            if cameraStatus == .authorized {
                if settings.cameraDeviceID == nil {
                    await enableDefaultCameraSource()
                } else {
                    refreshCameraDevices()
                    closeCameraPreviewOutsideRecording()
                }
            } else {
                closeCameraPreviewOutsideRecording()
            }
        }
    }

    func sourcePermissionPresentation(
        for source: CapturePermissionSource
    ) -> CaptureSourcePermissionPresentation {
        captureCapabilities.presentation(for: source)
    }

    var captureCapabilities: CaptureCapabilityState {
        CaptureCapabilityState(
            screenRecordingStatus: screenRecordingStatus,
            microphoneStatus: microphoneStatus,
            cameraStatus: cameraStatus,
            recordsSystemAudio: settings.recordSystemAudio,
            recordsMicrophone: settings.recordAudio,
            hasCameraSelection: settings.cameraDeviceID != nil,
            hasSelectedCaptureTarget: selectedCaptureTarget != nil,
            hasLastCaptureMemory: settings.lastCaptureMemory != nil
        )
    }

    private func enableCaptureSource(_ source: CapturePermissionSource) {
        switch source {
        case .screenPixels:
            break
        case .systemAudio:
            settings.recordSystemAudio = true
            saveSettings()
        case .microphone:
            settings.recordAudio = true
            saveSettings()
        case .camera:
            break
        }
    }

    private func permissionGuidance(for permission: SystemPermission) -> PermissionGuidance {
        permissionGuidanceService.guidance(
            for: permission,
            status: permissionStatus(for: permission)
        )
    }

    private func permissionGuidance(for source: CapturePermissionSource) -> PermissionGuidance {
        let presentation = sourcePermissionPresentation(for: source)

        return permissionGuidanceService.guidance(
            for: source,
            presentation: presentation,
            status: permissionStatus(for: source.systemPermission)
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
        case .inputMonitoring:
            inputMonitoringStatus
        }
    }
}
