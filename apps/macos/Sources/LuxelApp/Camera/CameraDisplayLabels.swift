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
            LuxelLocalization.string("cameraOverlay.shape.squircle", defaultValue: "Squircle")
        case .roundedRect:
            LuxelLocalization.string("cameraOverlay.shape.rounded", defaultValue: "Rounded")
        case .square:
            LuxelLocalization.string("cameraOverlay.shape.square", defaultValue: "Square")
        case .cutout:
            LuxelLocalization.string("cameraOverlay.shape.cutout", defaultValue: "Cutout")
        }
    }

    var settingsHelp: String {
        if usesPortraitMatting {
            return LuxelLocalization.string(
                "cameraOverlay.shape.cutoutHelp",
                defaultValue: "Remove the camera background and show only the presenter."
            )
        }

        return LuxelLocalization.format(
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
