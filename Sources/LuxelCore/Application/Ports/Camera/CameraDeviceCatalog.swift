public protocol CameraDeviceCatalog: Sendable {
    func availableCameraDevices() -> [CameraDeviceOption]
}
