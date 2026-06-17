import LuxelCore
import Testing

@Suite("Camera device service")
struct CameraDeviceServiceTests {
    @Test("availableCameraDevices returns selectable camera devices")
    func availableCameraDevicesReturnsSelectableCameraDevices() {
        let builtIn = CameraDeviceOption(id: "built-in", name: "FaceTime HD", kind: .builtIn)
        let external = CameraDeviceOption(id: "external", name: "USB Camera", kind: .external)
        let continuity = CameraDeviceOption(id: "continuity", name: "iPhone Camera", kind: .continuity)
        let service = CameraDeviceService(catalog: FakeCameraDeviceCatalog(devices: [
            builtIn,
            external,
            continuity
        ]))

        #expect(service.availableCameraDevices() == [builtIn, external, continuity])
    }

    @Test("availableCameraDevices excludes Desk View and duplicate device IDs")
    func availableCameraDevicesExcludesDeskViewAndDuplicateDeviceIDs() {
        let builtIn = CameraDeviceOption(id: "built-in", name: "FaceTime HD", kind: .builtIn)
        let service = CameraDeviceService(catalog: FakeCameraDeviceCatalog(devices: [
            CameraDeviceOption(id: "desk-view", name: "Desk View", kind: .deskView),
            builtIn,
            CameraDeviceOption(id: "built-in", name: "FaceTime HD Duplicate", kind: .builtIn)
        ]))

        #expect(service.availableCameraDevices() == [builtIn])
    }

    @Test("selectedCameraDevice resolves the selected camera by ID")
    func selectedCameraDeviceResolvesSelectedCameraByID() {
        let builtIn = CameraDeviceOption(id: "built-in", name: "FaceTime HD", kind: .builtIn)
        let external = CameraDeviceOption(id: "external", name: "USB Camera", kind: .external)
        let service = CameraDeviceService(catalog: FakeCameraDeviceCatalog(devices: []))

        #expect(service.selectedCameraDevice(selectedID: "external", in: [builtIn, external]) == external)
        #expect(service.selectedCameraDevice(selectedID: nil, in: [builtIn, external]) == nil)
        #expect(service.selectedCameraDevice(selectedID: "missing", in: [builtIn, external]) == nil)
    }

    @Test("defaultCameraDevice prefers built-in camera")
    func defaultCameraDevicePrefersBuiltInCamera() {
        let external = CameraDeviceOption(id: "external", name: "USB Camera", kind: .external)
        let builtIn = CameraDeviceOption(id: "built-in", name: "FaceTime HD", kind: .builtIn)
        let continuity = CameraDeviceOption(id: "continuity", name: "iPhone Camera", kind: .continuity)
        let service = CameraDeviceService(catalog: FakeCameraDeviceCatalog(devices: []))

        #expect(service.defaultCameraDevice(in: [external, builtIn, continuity]) == builtIn)
        #expect(service.defaultCameraDevice(in: [external, continuity]) == external)
        #expect(service.defaultCameraDevice(in: []) == nil)
    }
}

private struct FakeCameraDeviceCatalog: CameraDeviceCatalog {
    let devices: [CameraDeviceOption]

    func availableCameraDevices() -> [CameraDeviceOption] {
        devices
    }
}
