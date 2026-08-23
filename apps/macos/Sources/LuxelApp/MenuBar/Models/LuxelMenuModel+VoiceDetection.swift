import AppKit
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func watchVoiceDetectionLifecycle() async {
        await refreshPermissions()
        refreshAudioInputDevices()
        await reconcileVoiceDetection()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.watchVoiceDetectionStatuses()
            }
            group.addTask { [weak self] in
                await self?.watchVoiceDetectionSystemActivity()
            }
            group.addTask { [weak self] in
                await self?.watchVoiceDetectionAudioDevices()
            }
            await group.waitForAll()
        }
    }

    func reconcileVoiceDetection() async {
        let eligibility = await voiceDetectionEligibility()
        guard !Task.isCancelled else {
            return
        }

        if eligibility.canRunDetector {
            voiceDetectionStatus = .preparing
        }
        voiceDetectionStatus = await voiceDetection.coordinator.reconcile(
            eligibility: eligibility
        )
    }

    func scheduleVoiceDetectionReconciliation() {
        voiceDetection.reconcileTask?.cancel()
        voiceDetection.reconcileTask = Task { @MainActor [weak self] in
            await self?.reconcileVoiceDetection()
        }
    }

    func requestVoiceDetectionNotificationAuthorization()
        async -> VoiceDetectionAuthorizationStatus
    {
        let status = await voiceDetection.coordinator.requestNotificationAuthorization()
        scheduleVoiceDetectionReconciliation()
        return status
    }

    func approveVoiceDetectionDisclosure() async {
        settings.speechDetectionDisclosureAccepted = true
        settings.speechDetectionPromptsEnabled = true
        saveSettings()

        _ = await voiceDetection.coordinator.requestNotificationAuthorization()
        microphoneStatus = await permissionClient.request(.microphone)
        await reconcileVoiceDetection()
    }

    func cancelVoiceDetectionDisclosure() async {
        settings.speechDetectionDisclosureAccepted = false
        settings.speechDetectionPromptsEnabled = false
        saveSettings()
        await reconcileVoiceDetection()
    }

    func enablePreviouslyDisclosedVoiceDetection() async {
        guard settings.speechDetectionDisclosureAccepted else {
            return
        }
        settings.speechDetectionPromptsEnabled = true
        saveSettings()

        _ = await voiceDetection.coordinator.requestNotificationAuthorization()
        microphoneStatus = await permissionClient.request(.microphone)
        await reconcileVoiceDetection()
    }

    func disableVoiceDetectionPrompts() async {
        settings.speechDetectionPromptsEnabled = false
        saveSettings()
        await reconcileVoiceDetection()
    }

    func recoverVoiceDetectionMicrophoneAccess() async {
        if microphoneStatus == .notDetermined || microphoneStatus == .unknown {
            microphoneStatus = await permissionClient.request(.microphone)
        } else if microphoneStatus != .authorized {
            await permissionClient.openSettings(for: .microphone)
        }
        await reconcileVoiceDetection()
    }

    func recoverVoiceDetectionNotificationAccess() async {
        _ = await voiceDetection.coordinator.recoverNotificationAuthorization()
        await reconcileVoiceDetection()
    }

    func handleVoiceDetectionPromptAction(_ action: VoiceDetectionPromptAction) async {
        await refreshPermissions()
        await reconcileVoiceDetection()
        let outcome = await voiceDetection.coordinator.handlePromptAction(action)

        switch outcome {
        case .startRecording:
            await startSpeechPromptAudioOnlyRecording()
        case .activateApplication:
            NSApplication.shared.activate(ignoringOtherApps: true)
        case .none:
            break
        }
    }

    func shutdownVoiceDetection() async {
        voiceDetection.reconcileTask?.cancel()
        voiceDetection.reconcileTask = nil
        await voiceDetection.coordinator.shutdown()
        voiceDetectionStatus = .off
    }

    private func voiceDetectionEligibility() async -> VoiceDetectionEligibility {
        let notificationPermission =
            await voiceDetection.coordinator.notificationAuthorizationStatus()
        voiceDetectionNotificationStatus = notificationPermission
        let microphone = selectedVoiceDetectionMicrophone()

        return VoiceDetectionEligibility(
            isEnabled: settings.speechDetectionPromptsEnabled,
            isDisclosureAccepted: settings.speechDetectionDisclosureAccepted,
            notificationPermission: notificationPermission,
            microphonePermission: microphoneStatus.voiceDetectionAuthorizationStatus,
            microphone: microphone,
            isModelAvailable: voiceDetection.modelLocator.modelURL != nil,
            isDetectorReady: true,
            isRecordingLifecycleIdle: canBeginRecordingStart,
            isSessionLocked: voiceDetection.pauseReasons.contains(.locked),
            isDisplayAsleep: voiceDetection.pauseReasons.contains(.displaySleep)
        )
    }

    private func selectedVoiceDetectionMicrophone() -> VoiceDetectionMicrophone? {
        audioInputDevices = audioInputDeviceService.availableInputDevices()
        let selectedID = settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        guard let device = audioInputDevices.first(where: { $0.id == selectedID }) else {
            return nil
        }

        return VoiceDetectionMicrophone(
            deviceID: device.id == AudioInputDeviceID.systemDefault ? nil : device.id,
            name: device.name
        )
    }

    private func watchVoiceDetectionStatuses() async {
        for await status in voiceDetection.coordinator.statusUpdates {
            guard !Task.isCancelled else {
                return
            }
            voiceDetectionStatus = status
        }
    }

    private func watchVoiceDetectionAudioDevices() async {
        for await _ in audioInputDeviceService.inputDeviceUpdates() {
            guard !Task.isCancelled else {
                return
            }
            refreshAudioInputDevices()
            await reconcileVoiceDetection()
        }
    }

    private func watchVoiceDetectionSystemActivity() async {
        voiceDetection.pauseReasons = voiceDetection.systemActivityMonitor.currentPauseReasons
            .intersection([.locked, .displaySleep])

        for await event in voiceDetection.systemActivityMonitor.events() {
            guard !Task.isCancelled else {
                return
            }
            await handleVoiceDetectionSystemActivity(event)
        }
    }

    private func handleVoiceDetectionSystemActivity(_ event: SystemActivityEvent) async {
        switch event {
        case .pauseReasonBecameActive(let reason) where reason == .locked || reason == .displaySleep:
            voiceDetection.pauseReasons.insert(reason)
        case .pauseReasonBecameInactive(let reason) where reason == .locked || reason == .displaySleep:
            voiceDetection.pauseReasons.remove(reason)
        case .applicationDidBecomeActive:
            await refreshPermissions()
        case .displayConfigurationChanged:
            refreshAudioInputDevices()
        case .pauseReasonBecameActive, .pauseReasonBecameInactive:
            return
        }
        await reconcileVoiceDetection()
    }
}

extension PermissionStatus {
    fileprivate var voiceDetectionAuthorizationStatus: VoiceDetectionAuthorizationStatus {
        switch self {
        case .notDetermined, .unknown:
            .notDetermined
        case .authorized:
            .authorized
        case .denied, .restricted:
            .denied
        }
    }
}
