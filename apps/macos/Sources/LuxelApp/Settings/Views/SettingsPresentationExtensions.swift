import LuxelCore
import SwiftUI

extension ScreenshotFormat {
    var settingsLabel: String {
        switch self {
        case .png:
            "PNG"
        case .jpeg:
            "JPEG"
        case .heic:
            "HEIC"
        }
    }
}

extension ScreenshotDestination {
    var settingsLabel: String {
        switch self {
        case .clipboard:
            "Copy to Clipboard"
        case .file:
            "Save File"
        case .preview:
            "Open Preview"
        }
    }
}

extension CaptureBackdrop {
    var settingsLabel: String {
        switch self {
        case .opaque:
            "Opaque"
        case .transparent:
            "Transparent"
        case .transparentWithShadow:
            "Transparent + Shadow"
        }
    }
}

extension CommandLineToolInstallStatus {
    var message: String {
        switch self {
        case .installed(let destination):
            "Installed at \(destination.path)"
        case .failed(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .installed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .installed:
            .secondary
        case .failed:
            .orange
        }
    }
}
