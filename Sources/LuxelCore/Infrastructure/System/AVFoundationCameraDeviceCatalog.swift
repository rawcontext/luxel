import AVFoundation

public struct AVFoundationCameraDeviceCatalog: CameraDeviceCatalog {
    public init() {}

    public func availableCameraDevices() -> [CameraDeviceOption] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )

        return session.devices
            .filter { $0.deviceType != .deskViewCamera }
            .map { device in
                CameraDeviceOption(
                    id: device.uniqueID,
                    name: device.localizedName,
                    kind: Self.kind(for: device.deviceType)
                )
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func kind(for deviceType: AVCaptureDevice.DeviceType) -> CameraDeviceKind {
        switch deviceType {
        case .builtInWideAngleCamera:
            .builtIn
        case .external:
            .external
        case .continuityCamera:
            .continuity
        case .deskViewCamera:
            .deskView
        default:
            .unknown
        }
    }
}
