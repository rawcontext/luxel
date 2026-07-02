import LuxelCore
import SwiftUI

extension CommandLineToolInstallStatus {
    var message: String {
        switch self {
        case .installed(let destination):
            "Installed at \(destination.path)"
        case .repaired(let destination):
            "Repaired at \(destination.path)"
        case .pathCommandCopied(let destination):
            "PATH command copied for \(destination.deletingLastPathComponent().path)"
        case .failed(let message):
            message
        }
    }

    var systemImage: String {
        switch self {
        case .installed, .repaired:
            "checkmark.circle"
        case .pathCommandCopied:
            "doc.on.doc"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .installed, .repaired, .pathCommandCopied:
            .secondary
        case .failed:
            .orange
        }
    }
}
