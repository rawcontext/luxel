import LuxelCore
import SwiftUI

extension PermissionStatus {
    var title: String {
        switch self {
        case .notDetermined:
            LuxelLocalization.string("permissionStatus.ask", defaultValue: "Ask")
        case .authorized:
            LuxelLocalization.string("permissionStatus.allowed", defaultValue: "Allowed")
        case .denied:
            LuxelLocalization.string("permissionStatus.denied", defaultValue: "Denied")
        case .restricted:
            LuxelLocalization.string("permissionStatus.restricted", defaultValue: "Restricted")
        case .unknown:
            LuxelLocalization.string("permissionStatus.unknown", defaultValue: "Unknown")
        }
    }

    var symbolName: String {
        switch self {
        case .authorized:
            "checkmark.circle.fill"
        case .denied, .restricted:
            "exclamationmark.triangle.fill"
        case .notDetermined:
            "questionmark.circle"
        case .unknown:
            "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .authorized:
            .green
        case .denied, .restricted:
            .orange
        case .notDetermined, .unknown:
            .secondary
        }
    }
}
