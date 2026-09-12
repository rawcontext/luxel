import CoreGraphics
import LuxelCore

extension LuxelCropperModel {
    var primaryActionTitle: String {
        LuxelLocalization.string("Record")
    }

    var primaryActionSystemImage: String {
        "record.circle"
    }

    var primaryActionHelp: String {
        LuxelLocalization.string("Record the selected area.")
    }
}

extension CaptureResizeHandle {
    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .left:
            CGPoint(x: rect.minX, y: rect.midY)
        case .right:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight:
            CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    var helpTitle: String {
        switch self {
        case .topLeft:
            LuxelLocalization.string("Resize top left")
        case .top:
            LuxelLocalization.string("Resize top")
        case .topRight:
            LuxelLocalization.string("Resize top right")
        case .left:
            LuxelLocalization.string("Resize left")
        case .right:
            LuxelLocalization.string("Resize right")
        case .bottomLeft:
            LuxelLocalization.string("Resize bottom left")
        case .bottom:
            LuxelLocalization.string("Resize bottom")
        case .bottomRight:
            LuxelLocalization.string("Resize bottom right")
        }
    }
}
