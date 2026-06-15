import LuxelCore

extension CaptureTargetOption {
    var menuTitle: String {
        if let subtitle {
            return "\(title) - \(subtitle)"
        }

        return title
    }

    var systemImage: String {
        switch kind {
        case .display:
            "display"
        case .window:
            "macwindow"
        }
    }
}
