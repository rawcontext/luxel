import LuxelCore
import SwiftUI

extension PermissionStatus {
    var title: String {
        switch self {
        case .notDetermined:
            "Ask"
        case .authorized:
            "Allowed"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        case .unknown:
            "Unknown"
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
