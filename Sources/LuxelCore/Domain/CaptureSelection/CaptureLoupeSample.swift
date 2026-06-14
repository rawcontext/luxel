public enum CaptureLoupeSampleResolver {
    public static func sample(
        cursor: CapturePoint,
        display: DisplayBounds,
        selection: CaptureRect?,
        sampleSize: Int = 24,
        overlaySize: PixelSize,
        cursorOffset: Int = 18
    ) throws -> CaptureLoupeSample {
        guard sampleSize > 0, cursorOffset >= 0 else {
            throw CaptureModelError.invalidDimensions
        }

        let cursor = cursor.clamped(to: display)
        let sourceRect = try sourceRect(
            centeredAt: cursor,
            in: display,
            sampleSize: sampleSize
        )
        let placement = overlayPlacement(
            cursor: cursor,
            display: display,
            overlaySize: overlaySize,
            cursorOffset: cursorOffset
        )

        return CaptureLoupeSample(
            cursor: cursor,
            sourceRect: sourceRect,
            overlayOrigin: placement.origin,
            quadrant: placement.quadrant,
            readout: CaptureLoupeReadout(cursor: cursor, selection: selection)
        )
    }

    private static func sourceRect(
        centeredAt cursor: CapturePoint,
        in display: DisplayBounds,
        sampleSize: Int
    ) throws -> CaptureRect {
        let width = min(sampleSize, display.width)
        let height = min(sampleSize, display.height)
        let x = clamp(
            cursor.x - width / 2,
            minimum: 0,
            maximum: display.width - width
        )
        let y = clamp(
            cursor.y - height / 2,
            minimum: 0,
            maximum: display.height - height
        )

        return try CaptureRect(x: x, y: y, width: width, height: height)
    }

    private static func overlayPlacement(
        cursor: CapturePoint,
        display: DisplayBounds,
        overlaySize: PixelSize,
        cursorOffset: Int
    ) -> (origin: CapturePoint, quadrant: CaptureLoupeQuadrant) {
        let fitsRight = cursor.x + cursorOffset + overlaySize.width <= display.width
        let fitsBelow = cursor.y + cursorOffset + overlaySize.height <= display.height
        let x = fitsRight
            ? cursor.x + cursorOffset
            : cursor.x - cursorOffset - overlaySize.width
        let y = fitsBelow
            ? cursor.y + cursorOffset
            : cursor.y - cursorOffset - overlaySize.height
        let origin = CapturePoint(
            x: clamp(x, minimum: 0, maximum: max(0, display.width - overlaySize.width)),
            y: clamp(y, minimum: 0, maximum: max(0, display.height - overlaySize.height))
        )
        let quadrant = CaptureLoupeQuadrant(
            horizontal: fitsRight ? .right : .left,
            vertical: fitsBelow ? .below : .above
        )

        return (origin, quadrant)
    }

    private static func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(max(value, minimum), maximum)
    }
}

public struct CaptureLoupeSample: Equatable, Sendable {
    public let cursor: CapturePoint
    public let sourceRect: CaptureRect
    public let overlayOrigin: CapturePoint
    public let quadrant: CaptureLoupeQuadrant
    public let readout: CaptureLoupeReadout

    public init(
        cursor: CapturePoint,
        sourceRect: CaptureRect,
        overlayOrigin: CapturePoint,
        quadrant: CaptureLoupeQuadrant,
        readout: CaptureLoupeReadout
    ) {
        self.cursor = cursor
        self.sourceRect = sourceRect
        self.overlayOrigin = overlayOrigin
        self.quadrant = quadrant
        self.readout = readout
    }
}

public struct CaptureLoupeReadout: Equatable, Sendable {
    public let cursor: CapturePoint
    public let selection: CaptureRect?

    public init(cursor: CapturePoint, selection: CaptureRect?) {
        self.cursor = cursor
        self.selection = selection
    }
}

public enum CaptureLoupeQuadrant: Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    fileprivate init(horizontal: HorizontalPlacement, vertical: VerticalPlacement) {
        switch (horizontal, vertical) {
        case (.left, .above):
            self = .topLeft
        case (.right, .above):
            self = .topRight
        case (.left, .below):
            self = .bottomLeft
        case (.right, .below):
            self = .bottomRight
        }
    }
}

private enum HorizontalPlacement {
    case left
    case right
}

private enum VerticalPlacement {
    case above
    case below
}

private extension CapturePoint {
    func clamped(to display: DisplayBounds) -> CapturePoint {
        CapturePoint(
            x: min(max(x, 0), display.width),
            y: min(max(y, 0), display.height)
        )
    }
}
