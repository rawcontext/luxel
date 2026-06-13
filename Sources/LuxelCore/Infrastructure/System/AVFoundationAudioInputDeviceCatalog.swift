import AVFoundation

public struct AVFoundationAudioInputDeviceCatalog: AudioInputDeviceCatalog {
    public init() {}

    public func availableAudioInputDevices() -> [AudioInputDeviceOption] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        return session.devices
            .map { device in
                AudioInputDeviceOption(id: device.uniqueID, name: device.localizedName)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}
