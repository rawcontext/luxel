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

    @Test("inputDeviceUpdates forwards update source events")
    func inputDeviceUpdatesForwardsUpdateSourceEvents() async {
        let stream = AsyncStream<Void> { continuation in
            continuation.yield(())
            continuation.finish()
        }
        let service = AudioInputDeviceService(
            catalog: FakeAudioInputDeviceCatalog(devices: []),
            updateSource: FakeAudioInputDeviceUpdateSource(stream: stream)
        )

        var iterator = service.inputDeviceUpdates().makeAsyncIterator()

        #expect(await iterator.next() != nil)
        #expect(await iterator.next() == nil)
    }

    @Test("resolveInputDevice keeps an exact device ID match")
    func resolveInputDeviceKeepsExactIDMatch() {
        let service = AudioInputDeviceService(catalog: FakeAudioInputDeviceCatalog(devices: []))
        let devices = [
            AudioInputDeviceOption.systemDefault,
            AudioInputDeviceOption(id: "mic-1", name: "Studio Mic")
        ]

        let resolution = service.resolveInputDevice(
            selectedID: "mic-1",
            selectedName: "Studio Mic",
            in: devices
        )

        #expect(resolution.device == AudioInputDeviceOption(id: "mic-1", name: "Studio Mic"))
        #expect(!resolution.fellBackToSystemDefault)
        #expect(resolution.microphoneDeviceID == "mic-1")
        #expect(resolution.fallbackMessage == nil)
    }

    @Test("resolveInputDevice falls back to matching device name when ID changed")
    func resolveInputDeviceFallsBackToMatchingNameWhenIDChanged() {
        let service = AudioInputDeviceService(catalog: FakeAudioInputDeviceCatalog(devices: []))
        let devices = [
            AudioInputDeviceOption.systemDefault,
            AudioInputDeviceOption(id: "mic-2", name: "Studio Mic")
        ]

        let resolution = service.resolveInputDevice(
            selectedID: "mic-1",
            selectedName: "Studio Mic",
            in: devices
        )

        #expect(resolution.device == AudioInputDeviceOption(id: "mic-2", name: "Studio Mic"))
        #expect(!resolution.fellBackToSystemDefault)
        #expect(resolution.microphoneDeviceID == "mic-2")
    }

    @Test("resolveInputDevice falls back to system default when selected device is missing")
    func resolveInputDeviceFallsBackToSystemDefaultWhenSelectedDeviceIsMissing() {
        let service = AudioInputDeviceService(catalog: FakeAudioInputDeviceCatalog(devices: []))
        let devices = [
            AudioInputDeviceOption.systemDefault,
            AudioInputDeviceOption(id: "mic-2", name: "Desk Mic")
        ]

        let resolution = service.resolveInputDevice(
            selectedID: "mic-1",
            selectedName: "Studio Mic",
            in: devices
        )

        #expect(resolution.device == .systemDefault)
        #expect(resolution.fellBackToSystemDefault)
        #expect(resolution.microphoneDeviceID == nil)
        #expect(resolution.fallbackMessage == "Mic 'Studio Mic' not found - using System Default.")
    }
}

private struct FakeAudioInputDeviceCatalog: AudioInputDeviceCatalog {
    let devices: [AudioInputDeviceOption]

    func availableAudioInputDevices() -> [AudioInputDeviceOption] {
        devices
    }
}

private struct FakeAudioInputDeviceUpdateSource: AudioInputDeviceUpdateSource {
    let stream: AsyncStream<Void>

    func inputDeviceUpdates() -> AsyncStream<Void> {
        stream
    }
}
