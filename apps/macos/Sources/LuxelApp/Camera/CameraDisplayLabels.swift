import LuxelCore

extension CameraDeviceOption {
    var settingsLabel: String {
        "\(name) (\(kind.settingsLabel))"
    }
}

extension CameraDeviceKind {
    var settingsLabel: String {
        switch self {
        case .builtIn:
            "Built-In"
        case .external:
            "External"
        case .continuity:
            "Continuity"
        case .deskView:
            "Desk View"
        case .unknown:
            "Camera"
        }
    }
}

extension CameraOverlayShape {
    var settingsLabel: String {
        switch self {
        case .circle:
            "Circle"
        case .roundedRect:
            "Rounded"
        }
    }
}

extension CameraPreviewSize {
    var settingsLabel: String {
        switch self {
        case .small:
            "S"
        case .medium:
            "M"
        case .large:
            "L"
        }
    }
}
