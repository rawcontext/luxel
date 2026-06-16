import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshAudioInputDevices() {
        _ = resolveSelectedAudioInputDevice()
    }

    func watchAudioInputDeviceUpdates() async {
        for await _ in audioInputDeviceService.inputDeviceUpdates() {
            refreshAudioInputDevices()
        }
    }

    func watchAudioLevels(onlyWhenRecording: Bool = false) async {
        let audioLevelMonitor = audioLevelMonitorFactory()
        defer {
            audioLevelMonitor.stop()
        }

        audioLevelSample = .silent

        guard microphoneStatus == .authorized else {
            return
        }

        let microphoneDeviceID: String?
        if onlyWhenRecording {
            guard let activeRecording = recordingState.activeRecording,
                  activeRecording.options.audio.capturesMicrophone else {
                return
            }

            microphoneDeviceID = activeRecording.options.audio.microphoneDeviceID
        } else {
            guard settings.recordAudio else {
                return
            }

            microphoneDeviceID = resolveSelectedAudioInputDevice().microphoneDeviceID
        }

        for await sample in audioLevelMonitor.start(deviceID: microphoneDeviceID) {
            audioLevelSample = sample
        }
    }

    func cropperAudioLevelConfiguration() -> CropperAudioLevelConfiguration? {
        guard microphoneStatus == .authorized else {
            return nil
        }

        let resolution = resolveSelectedAudioInputDevice()

        return CropperAudioLevelConfiguration(deviceID: resolution.microphoneDeviceID)
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
