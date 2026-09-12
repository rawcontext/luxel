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
            LuxelLocalization.string("Built-In")
        case .external:
            LuxelLocalization.string("External")
        case .continuity:
            LuxelLocalization.string("Continuity")
        case .deskView:
            LuxelLocalization.string("Desk View")
        case .unknown:
            LuxelLocalization.string("Camera")
        }
    }
}

extension CameraOverlayShape {
    var settingsLabel: String {
        switch self {
        case .circle:
            LuxelLocalization.string("cameraOverlay.shape.squircle", defaultValue: "Squircle")
        case .roundedRect:
            LuxelLocalization.string("cameraOverlay.shape.rounded", defaultValue: "Rounded")
        case .square:
            LuxelLocalization.string("cameraOverlay.shape.square", defaultValue: "Square")
        }
    }

    var settingsHelp: String {
        LuxelLocalization.format(
            "cameraOverlay.shape.optionHelp",
            defaultValue: "Set the camera overlay shape to %@.",
            settingsLabel
        )
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
