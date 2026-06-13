import LuxelCore
import Testing

@Suite("Audio input device service")
struct AudioInputDeviceServiceTests {
    @Test("availableInputDevices prepends the system default device")
    func availableInputDevicesPrependsSystemDefaultDevice() {
        let catalog = FakeAudioInputDeviceCatalog(devices: [
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic")
        ])
        let service = AudioInputDeviceService(catalog: catalog)

        #expect(service.availableInputDevices() == [
            .systemDefault,
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic")
        ])
    }

    @Test("availableInputDevices removes duplicate device IDs")
    func availableInputDevicesRemovesDuplicateDeviceIDs() {
        let catalog = FakeAudioInputDeviceCatalog(devices: [
            AudioInputDeviceOption(id: AudioInputDeviceID.systemDefault, name: "Duplicate Default"),
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic"),
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic Duplicate")
        ])
        let service = AudioInputDeviceService(catalog: catalog)

        #expect(service.availableInputDevices() == [
            .systemDefault,
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic")
        ])
    }
}

private struct FakeAudioInputDeviceCatalog: AudioInputDeviceCatalog {
    let devices: [AudioInputDeviceOption]

    func availableAudioInputDevices() -> [AudioInputDeviceOption] {
        devices
    }
}
