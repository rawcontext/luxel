import LuxelCore
import SwiftUI

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
