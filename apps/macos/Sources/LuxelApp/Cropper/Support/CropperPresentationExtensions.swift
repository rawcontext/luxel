import CoreGraphics
import LuxelCore

extension LuxelCropperMode {
    var toolbarLabel: String {
        switch self {
        case .video:
            "Video"
        case .photo:
            "Photo"
        }
    }
}

extension LuxelCropperModel {
    var primaryActionTitle: String {
        switch mode {
        case .video:
            "Record"
        case .photo:
            "Capture"
        }
    }

    var primaryActionSystemImage: String {
        switch mode {
        case .video:
            "record.circle"
        case .photo:
            "camera"
        }
    }

    var primaryActionHelp: String {
        switch mode {
        case .video:
            "Record the selected area."
        case .photo:
            "Capture the selected area as a screenshot."
        }
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
            "Resize top left"
        case .top:
            "Resize top"
        case .topRight:
            "Resize top right"
        case .left:
            "Resize left"
        case .right:
            "Resize right"
        case .bottomLeft:
            "Resize bottom left"
        case .bottom:
            "Resize bottom"
        case .bottomRight:
            "Resize bottom right"
        }
    }
}
