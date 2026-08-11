import LuxelCore

extension CaptureResizeHandle {
    func cursorPoint(in selection: CaptureRect?) -> CapturePoint {
        guard let selection else {
            return CapturePoint(x: 0, y: 0)
        }

        let midX = selection.originX + selection.width / 2
        let midY = selection.originY + selection.height / 2
        let maxX = selection.originX + selection.width
        let maxY = selection.originY + selection.height

        return switch self {
        case .topLeft:
            CapturePoint(x: selection.originX, y: selection.originY)
        case .top:
            CapturePoint(x: midX, y: selection.originY)
        case .topRight:
            CapturePoint(x: maxX, y: selection.originY)
        case .left:
            CapturePoint(x: selection.originX, y: midY)
        case .right:
            CapturePoint(x: maxX, y: midY)
        case .bottomLeft:
            CapturePoint(x: selection.originX, y: maxY)
        case .bottom:
            CapturePoint(x: midX, y: maxY)
        case .bottomRight:
            CapturePoint(x: maxX, y: maxY)
        }
    }
}
