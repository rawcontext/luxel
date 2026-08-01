public enum CaptureResizeHandle: Codable, CaseIterable, Equatable, Hashable, Sendable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

public struct CaptureResizeDelta: Codable, Equatable, Sendable {
    public let deltaX: Int
    public let deltaY: Int

    public init(x deltaX: Int, y deltaY: Int) {
        self.deltaX = deltaX
        self.deltaY = deltaY
    }

    private enum CodingKeys: String, CodingKey {
        case deltaX = "x"
        case deltaY = "y"
    }
}

public enum CaptureSelectionBuilder {
    public static func fullDisplaySelection(in display: DisplayBounds) throws -> CaptureRect {
        try CaptureRect(x: 0, y: 0, width: display.width, height: display.height)
    }

    public static func selection(
        from start: CapturePoint,
        to end: CapturePoint,
        in display: DisplayBounds,
        aspectRatio: CaptureAspectRatio? = nil,
        minimumSize: Int = 32
    ) throws -> CaptureRect {
        guard minimumSize > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        let clampedStart = start.clamped(to: display)
        let clampedEnd = end.clamped(to: display)
        let growsLeft = clampedEnd.xCoordinate < clampedStart.xCoordinate
        let growsUp = clampedEnd.yCoordinate < clampedStart.yCoordinate
        var width = max(minimumSize, abs(clampedEnd.xCoordinate - clampedStart.xCoordinate))
        var height = max(minimumSize, abs(clampedEnd.yCoordinate - clampedStart.yCoordinate))

        if let aspectRatio {
            (width, height) = size(
                width: width,
                height: height,
                aspectRatio: aspectRatio,
                maximum: (
                    width: growsLeft ? clampedStart.xCoordinate : display.width - clampedStart.xCoordinate,
                    height: growsUp ? clampedStart.yCoordinate : display.height - clampedStart.yCoordinate
                ),
                minimumSize: minimumSize
            )
        }

        width = min(width, display.width)
        height = min(height, display.height)

        let originX =
            growsLeft
            ? max(0, clampedStart.xCoordinate - width)
            : min(clampedStart.xCoordinate, display.width - width)
        let originY =
            growsUp
            ? max(0, clampedStart.yCoordinate - height)
            : min(clampedStart.yCoordinate, display.height - height)

        return try CaptureRect(x: originX, y: originY, width: width, height: height)
    }

    private static func size(
        width: Int,
        height: Int,
        aspectRatio: CaptureAspectRatio,
        maximum: (width: Int, height: Int),
        minimumSize: Int
    ) -> (width: Int, height: Int) {
        let ratio = aspectRatio.value
        var outputWidth = max(width, Int((Double(height) * ratio).rounded()))
        var outputHeight = Int((Double(outputWidth) / ratio).rounded())

        if outputHeight > maximum.height {
            outputHeight = max(minimumSize, maximum.height)
            outputWidth = Int((Double(outputHeight) * ratio).rounded())
        }

        if outputWidth > maximum.width {
            outputWidth = max(minimumSize, maximum.width)
            outputHeight = Int((Double(outputWidth) / ratio).rounded())
        }

        return (max(minimumSize, outputWidth), max(minimumSize, outputHeight))
    }
}

extension CapturePoint {
    func clamped(to display: DisplayBounds) -> CapturePoint {
        CapturePoint(
            x: min(max(xCoordinate, 0), display.width),
            y: min(max(yCoordinate, 0), display.height)
        )
    }
}

extension CaptureResizeHandle {
    var isCorner: Bool {
        switch self {
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            true
        case .top, .left, .right, .bottom:
            false
        }
    }

    var movesLeftEdge: Bool {
        switch self {
        case .topLeft, .left, .bottomLeft:
            true
        case .top, .topRight, .right, .bottom, .bottomRight:
            false
        }
    }

    var movesRightEdge: Bool {
        switch self {
        case .topRight, .right, .bottomRight:
            true
        case .topLeft, .top, .left, .bottomLeft, .bottom:
            false
        }
    }

    var movesTopEdge: Bool {
        switch self {
        case .topLeft, .top, .topRight:
            true
        case .left, .right, .bottomLeft, .bottom, .bottomRight:
            false
        }
    }

    var movesBottomEdge: Bool {
        switch self {
        case .bottomLeft, .bottom, .bottomRight:
            true
        case .topLeft, .top, .topRight, .left, .right:
            false
        }
    }
}
