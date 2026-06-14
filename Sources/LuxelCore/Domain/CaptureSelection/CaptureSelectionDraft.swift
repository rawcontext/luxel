public struct CaptureSelectionDraft: Codable, Equatable, Sendable {
    public let display: DisplayBounds
    public let topLeftSelection: CaptureRect
    public let minimumWidth: Int
    public let minimumHeight: Int

    public init(
        display: DisplayBounds,
        topLeftSelection: CaptureRect,
        minimumWidth: Int = 32,
        minimumHeight: Int = 32
    ) throws {
        guard minimumWidth > 0,
              minimumHeight > 0,
              minimumWidth <= display.width,
              minimumHeight <= display.height else {
            throw CaptureModelError.invalidDimensions
        }

        _ = try CaptureCoordinateMapper.recordingRect(fromTopLeftSelection: topLeftSelection, in: display)
        self.display = display
        self.topLeftSelection = topLeftSelection
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
    }

    public var pixelSize: PixelSize {
        get throws {
            try PixelSize(width: topLeftSelection.width, height: topLeftSelection.height)
        }
    }

    public var captureTarget: CaptureTarget {
        get throws {
            let recordingRect = try CaptureCoordinateMapper.recordingRect(
                fromTopLeftSelection: topLeftSelection,
                in: display
            )
            return .area(displayID: display.id, rect: recordingRect)
        }
    }

    public func resized(
        dragging handle: CaptureResizeHandle,
        by delta: CaptureResizeDelta,
        lockingAspectRatio: Bool = false
    ) throws -> CaptureSelectionDraft {
        let rect = if lockingAspectRatio, handle.isCorner {
            try aspectLockedResize(dragging: handle, by: delta)
        } else {
            try freeformResize(dragging: handle, by: delta)
        }

        return try CaptureSelectionDraft(
            display: display,
            topLeftSelection: rect,
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
    }

    public func replacingSelection(
        x: Int? = nil,
        y: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) throws -> CaptureSelectionDraft {
        let resolvedWidth = clamp(
            width ?? topLeftSelection.width,
            minimum: minimumWidth,
            maximum: display.width
        )
        let resolvedHeight = clamp(
            height ?? topLeftSelection.height,
            minimum: minimumHeight,
            maximum: display.height
        )
        let resolvedX = clamp(
            x ?? topLeftSelection.x,
            minimum: 0,
            maximum: display.width - resolvedWidth
        )
        let resolvedY = clamp(
            y ?? topLeftSelection.y,
            minimum: 0,
            maximum: display.height - resolvedHeight
        )

        return try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(
                x: resolvedX,
                y: resolvedY,
                width: resolvedWidth,
                height: resolvedHeight
            ),
            minimumWidth: minimumWidth,
            minimumHeight: minimumHeight
        )
    }

    public func moved(by delta: CaptureResizeDelta) throws -> CaptureSelectionDraft {
        try replacingSelection(
            x: topLeftSelection.x + delta.x,
            y: topLeftSelection.y + delta.y
        )
    }

    public func resized(by delta: CaptureResizeDelta) throws -> CaptureSelectionDraft {
        try replacingSelection(
            width: topLeftSelection.width + delta.x,
            height: topLeftSelection.height + delta.y
        )
    }

    public func applyingAspectRatioPreset(_ preset: CaptureAspectRatioPreset) throws -> CaptureSelectionDraft {
        try applyingAspectRatio(preset.aspectRatio)
    }

    public func applyingAspectRatio(_ aspectRatio: CaptureAspectRatio?) throws -> CaptureSelectionDraft {
        guard let aspectRatio else {
            return self
        }

        let ratio = aspectRatio.value
        var width = max(topLeftSelection.width, minimumWidth)
        var height = Int((Double(width) / aspectRatio.value).rounded())

        if height < minimumHeight {
            height = minimumHeight
            width = Int((Double(height) * ratio).rounded())
        }

        if height > display.height {
            height = display.height
            width = Int((Double(height) * ratio).rounded())
        }

        if width > display.width {
            width = display.width
            height = Int((Double(width) / ratio).rounded())
        }

        if height > display.height {
            height = display.height
            width = Int((Double(height) * ratio).rounded())
        }

        return try replacingSelectionCentered(width: width, height: height)
    }

    public func applyingSizePreset(_ preset: CaptureSizePreset) throws -> CaptureSelectionDraft {
        try replacingSelectionCentered(
            width: preset.pixelSize.width,
            height: preset.pixelSize.height
        )
    }

    private func freeformResize(
        dragging handle: CaptureResizeHandle,
        by delta: CaptureResizeDelta
    ) throws -> CaptureRect {
        var left = topLeftSelection.x
        var top = topLeftSelection.y
        var right = topLeftSelection.x + topLeftSelection.width
        var bottom = topLeftSelection.y + topLeftSelection.height

        if handle.movesLeftEdge {
            left = min(max(left + delta.x, 0), right - minimumWidth)
        }

        if handle.movesRightEdge {
            right = max(min(right + delta.x, display.width), left + minimumWidth)
        }

        if handle.movesTopEdge {
            top = min(max(top + delta.y, 0), bottom - minimumHeight)
        }

        if handle.movesBottomEdge {
            bottom = max(min(bottom + delta.y, display.height), top + minimumHeight)
        }

        return try CaptureRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func aspectLockedResize(
        dragging handle: CaptureResizeHandle,
        by delta: CaptureResizeDelta
    ) throws -> CaptureRect {
        let ratio = Double(topLeftSelection.width) / Double(topLeftSelection.height)
        let left = topLeftSelection.x
        let top = topLeftSelection.y
        let right = topLeftSelection.x + topLeftSelection.width
        let bottom = topLeftSelection.y + topLeftSelection.height
        let maxWidth = handle.movesLeftEdge ? right : display.width - left
        let maxHeight = handle.movesTopEdge ? bottom : display.height - top
        let widthChange = Double(abs(delta.x)) / Double(topLeftSelection.width)
        let heightChange = Double(abs(delta.y)) / Double(topLeftSelection.height)
        var width = handle.movesLeftEdge ? right - (left + delta.x) : right + delta.x - left
        var height = handle.movesTopEdge ? bottom - (top + delta.y) : bottom + delta.y - top

        if widthChange >= heightChange {
            width = min(max(width, minimumWidth), maxWidth)
            height = Int((Double(width) / ratio).rounded())
        } else {
            height = min(max(height, minimumHeight), maxHeight)
            width = Int((Double(height) * ratio).rounded())
        }

        (width, height) = clampAspectLockedSize(
            width: width,
            height: height,
            ratio: ratio,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )

        let x = handle.movesLeftEdge ? right - width : left
        let y = handle.movesTopEdge ? bottom - height : top
        return try CaptureRect(x: x, y: y, width: width, height: height)
    }

    private func clampAspectLockedSize(
        width: Int,
        height: Int,
        ratio: Double,
        maxWidth: Int,
        maxHeight: Int
    ) -> (width: Int, height: Int) {
        var outputWidth = width
        var outputHeight = height

        if outputWidth < minimumWidth {
            outputWidth = minimumWidth
            outputHeight = Int((Double(outputWidth) / ratio).rounded())
        }

        if outputHeight < minimumHeight {
            outputHeight = minimumHeight
            outputWidth = Int((Double(outputHeight) * ratio).rounded())
        }

        if outputWidth > maxWidth {
            outputWidth = maxWidth
            outputHeight = Int((Double(outputWidth) / ratio).rounded())
        }

        if outputHeight > maxHeight {
            outputHeight = maxHeight
            outputWidth = Int((Double(outputHeight) * ratio).rounded())
        }

        return (
            max(1, min(outputWidth, maxWidth)),
            max(1, min(outputHeight, maxHeight))
        )
    }

    private func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        min(max(value, minimum), maximum)
    }

    private func replacingSelectionCentered(width: Int, height: Int) throws -> CaptureSelectionDraft {
        let resolvedWidth = clamp(width, minimum: minimumWidth, maximum: display.width)
        let resolvedHeight = clamp(height, minimum: minimumHeight, maximum: display.height)
        let centerX = Double(topLeftSelection.x) + Double(topLeftSelection.width) / 2
        let centerY = Double(topLeftSelection.y) + Double(topLeftSelection.height) / 2
        let x = clamp(
            Int((centerX - Double(resolvedWidth) / 2).rounded()),
            minimum: 0,
            maximum: display.width - resolvedWidth
        )
        let y = clamp(
            Int((centerY - Double(resolvedHeight) / 2).rounded()),
            minimum: 0,
            maximum: display.height - resolvedHeight
        )

        return try replacingSelection(x: x, y: y, width: resolvedWidth, height: resolvedHeight)
    }
}

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
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
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
        let growsLeft = clampedEnd.x < clampedStart.x
        let growsUp = clampedEnd.y < clampedStart.y
        var width = max(minimumSize, abs(clampedEnd.x - clampedStart.x))
        var height = max(minimumSize, abs(clampedEnd.y - clampedStart.y))

        if let aspectRatio {
            (width, height) = size(
                width: width,
                height: height,
                aspectRatio: aspectRatio,
                maxWidth: growsLeft ? clampedStart.x : display.width - clampedStart.x,
                maxHeight: growsUp ? clampedStart.y : display.height - clampedStart.y,
                minimumSize: minimumSize
            )
        }

        width = min(width, display.width)
        height = min(height, display.height)

        let x = growsLeft
            ? max(0, clampedStart.x - width)
            : min(clampedStart.x, display.width - width)
        let y = growsUp
            ? max(0, clampedStart.y - height)
            : min(clampedStart.y, display.height - height)

        return try CaptureRect(x: x, y: y, width: width, height: height)
    }

    private static func size(
        width: Int,
        height: Int,
        aspectRatio: CaptureAspectRatio,
        maxWidth: Int,
        maxHeight: Int,
        minimumSize: Int
    ) -> (width: Int, height: Int) {
        let ratio = aspectRatio.value
        var outputWidth = max(width, Int((Double(height) * ratio).rounded()))
        var outputHeight = Int((Double(outputWidth) / ratio).rounded())

        if outputHeight > maxHeight {
            outputHeight = max(minimumSize, maxHeight)
            outputWidth = Int((Double(outputHeight) * ratio).rounded())
        }

        if outputWidth > maxWidth {
            outputWidth = max(minimumSize, maxWidth)
            outputHeight = Int((Double(outputWidth) / ratio).rounded())
        }

        return (max(minimumSize, outputWidth), max(minimumSize, outputHeight))
    }
}

private extension CapturePoint {
    func clamped(to display: DisplayBounds) -> CapturePoint {
        CapturePoint(
            x: min(max(x, 0), display.width),
            y: min(max(y, 0), display.height)
        )
    }
}

private extension CaptureResizeHandle {
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
