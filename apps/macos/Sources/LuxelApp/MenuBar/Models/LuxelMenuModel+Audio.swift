import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshAudioInputDevices() {
        audioInputDevices = audioInputDeviceService.availableInputDevices()
        scheduleVoiceDetectionReconciliation()
    }

    func watchAudioInputDeviceUpdates() async {
        for await _ in audioInputDeviceService.inputDeviceUpdates() {
            refreshAudioInputDevices()
        }
    }

    func watchAudioLevels(onlyWhenRecording: Bool = false) async {
        if onlyWhenRecording {
            await watchRecordingAudioLevels()
            return
        }

        let audioLevelMonitor = audioLevelMonitorFactory()
        defer {
            audioLevelMonitor.stop()
        }

        audioLevelSample = .silent

        guard microphoneStatus == .authorized else {
            return
        }

        guard settings.recordAudio else {
            return
        }

        let microphoneDeviceID = resolveSelectedAudioInputDevice().microphoneDeviceID
        for await sample in audioLevelMonitor.start(deviceID: microphoneDeviceID) {
            audioLevelSample = sample
        }
    }

    private func watchRecordingAudioLevels() async {
        let audioLevelMonitor = recordingAudioLevelMonitorFactory()
        defer {
            audioLevelMonitor.stop()
        }

        audioLevelSample = .silent

        guard let activeRecording = recordingState.activeRecording,
            activeRecording.options.audio.capturesAudio
        else {
            return
        }

        for await sample in audioLevelMonitor.start(deviceID: nil) {
            audioLevelSample = sample
        }
    }

    @discardableResult
    func resolveSelectedAudioInputDevice() -> AudioInputDeviceResolution {
        audioInputDevices = audioInputDeviceService.availableInputDevices()
        let resolution = audioInputDeviceService.resolveInputDevice(
            selectedID: settings.audioInputDeviceID,
            selectedName: settings.audioInputDeviceName,
            in: audioInputDevices
        )

        if settings.audioInputDeviceID != resolution.device.id
            || settings.audioInputDeviceName != resolution.device.name {
            settings.audioInputDeviceID = resolution.device.id
            settings.audioInputDeviceName = resolution.device.name
            saveSettings()
        }

        return resolution
    }
}
