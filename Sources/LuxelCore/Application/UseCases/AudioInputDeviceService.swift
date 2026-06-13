public struct AudioInputDeviceService: Sendable {
    private let catalog: any AudioInputDeviceCatalog

    public init(catalog: any AudioInputDeviceCatalog) {
        self.catalog = catalog
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
}
