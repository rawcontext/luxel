public struct AudioInputDeviceService: Sendable {
    private let catalog: any AudioInputDeviceCatalog
    private let updateSource: any AudioInputDeviceUpdateSource

    public init(
        catalog: any AudioInputDeviceCatalog,
        updateSource: any AudioInputDeviceUpdateSource = EmptyAudioInputDeviceUpdateSource()
    ) {
        self.catalog = catalog
        self.updateSource = updateSource
    }

    public func availableInputDevices() -> [AudioInputDeviceOption] {
        var seenIDs = Set([AudioInputDeviceOption.systemDefault.id])
        var devices = [AudioInputDeviceOption.systemDefault]

        for device in catalog.availableAudioInputDevices() where !seenIDs.contains(device.id) {
            devices.append(device)
            seenIDs.insert(device.id)
        }

        return devices
    }

    public func inputDeviceUpdates() -> AsyncStream<Void> {
        updateSource.inputDeviceUpdates()
    }

    public func resolveInputDevice(
        selectedID: String?,
        selectedName: String?,
        in devices: [AudioInputDeviceOption]
    ) -> AudioInputDeviceResolution {
        let selectedID = selectedID ?? AudioInputDeviceID.systemDefault

        if let device = devices.first(where: { $0.id == selectedID }) {
            return AudioInputDeviceResolution(device: device, fellBackToSystemDefault: false)
        }

        if let selectedName {
            let matchingDevice = devices.first { device in
                device.id != AudioInputDeviceID.systemDefault && device.name == selectedName
            }

            if let matchingDevice {
                return AudioInputDeviceResolution(device: matchingDevice, fellBackToSystemDefault: false)
            }
        }

        return AudioInputDeviceResolution(
            device: .systemDefault,
            fellBackToSystemDefault: true,
            missingDeviceName: selectedName
        )
    }
}

public struct AudioInputDeviceResolution: Equatable, Sendable {
    public let device: AudioInputDeviceOption
    public let fellBackToSystemDefault: Bool
    public let missingDeviceName: String?

    public init(
        device: AudioInputDeviceOption,
        fellBackToSystemDefault: Bool,
        missingDeviceName: String? = nil
    ) {
        self.device = device
        self.fellBackToSystemDefault = fellBackToSystemDefault
        self.missingDeviceName = missingDeviceName
    }

    public var microphoneDeviceID: String? {
        device.id == AudioInputDeviceID.systemDefault ? nil : device.id
    }

    public var fallbackMessage: String? {
        guard fellBackToSystemDefault else {
            return nil
        }

        guard let missingDeviceName, !missingDeviceName.isEmpty else {
            return LuxelLocalization.string("Selected microphone not found - using System Default.")
        }

        return LuxelLocalization.format("Mic '%@' not found - using System Default.", missingDeviceName)
    }
}
