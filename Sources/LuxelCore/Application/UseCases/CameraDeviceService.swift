public struct CameraDeviceService: Sendable {
    private let catalog: any CameraDeviceCatalog

    public init(catalog: any CameraDeviceCatalog) {
        self.catalog = catalog
    }

    public func availableCameraDevices() -> [CameraDeviceOption] {
        var seenIDs = Set<String>()
        var devices: [CameraDeviceOption] = []

        for device in catalog.availableCameraDevices()
            where device.kind != .deskView && !seenIDs.contains(device.id) {
            devices.append(device)
            seenIDs.insert(device.id)
        }

        return devices
    }

    public func selectedCameraDevice(
        selectedID: String?,
        in devices: [CameraDeviceOption]
    ) -> CameraDeviceOption? {
        guard let selectedID else {
            return nil
        }

        return devices.first { $0.id == selectedID }
    }
}
