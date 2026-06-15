public protocol AudioInputDeviceCatalog: Sendable {
    func availableAudioInputDevices() -> [AudioInputDeviceOption]
}
