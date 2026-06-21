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
              minimumHeight <= display.height
        else {
            throw CaptureModelError.invalidDimensions
        }

        _ = try CaptureCoordinateMapper.recordingRect(
            fromTopLeftSelection: topLeftSelection, in: display)
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
        let rect =
            if lockingAspectRatio, handle.isCorner {
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
        x selectionX: Int? = nil,
        y selectionY: Int? = nil,
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
            selectionX ?? topLeftSelection.originX,
            minimum: 0,
            maximum: display.width - resolvedWidth
        )
        let resolvedY = clamp(
            selectionY ?? topLeftSelection.originY,
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
            x: topLeftSelection.originX + delta.deltaX,
            y: topLeftSelection.originY + delta.deltaY
        )
    }

    public func resized(by delta: CaptureResizeDelta) throws -> CaptureSelectionDraft {
        try replacingSelection(
            width: topLeftSelection.width + delta.deltaX,
            height: topLeftSelection.height + delta.deltaY
        )
    }

    public func applyingAspectRatioPreset(_ preset: CaptureAspectRatioPreset) throws
    -> CaptureSelectionDraft {
        try applyingAspectRatio(preset.aspectRatio)
    }

    public func applyingAspectRatio(_ aspectRatio: CaptureAspectRatio?) throws
    -> CaptureSelectionDraft {
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
        var left = topLeftSelection.originX
        var top = topLeftSelection.originY
        var right = topLeftSelection.originX + topLeftSelection.width
        var bottom = topLeftSelection.originY + topLeftSelection.height

        if handle.movesLeftEdge {
            left = min(max(left + delta.deltaX, 0), right - minimumWidth)
        }

        if handle.movesRightEdge {
            right = max(min(right + delta.deltaX, display.width), left + minimumWidth)
        }

        if handle.movesTopEdge {
            top = min(max(top + delta.deltaY, 0), bottom - minimumHeight)
        }

        if handle.movesBottomEdge {
            bottom = max(min(bottom + delta.deltaY, display.height), top + minimumHeight)
        }

        return try CaptureRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    private func aspectLockedResize(
        dragging handle: CaptureResizeHandle,
        by delta: CaptureResizeDelta
    ) throws -> CaptureRect {
        let ratio = Double(topLeftSelection.width) / Double(topLeftSelection.height)
        let left = topLeftSelection.originX
        let top = topLeftSelection.originY
        let right = topLeftSelection.originX + topLeftSelection.width
        let bottom = topLeftSelection.originY + topLeftSelection.height
        let maxWidth = handle.movesLeftEdge ? right : display.width - left
        let maxHeight = handle.movesTopEdge ? bottom : display.height - top
        let widthChange = Double(abs(delta.deltaX)) / Double(topLeftSelection.width)
        let heightChange = Double(abs(delta.deltaY)) / Double(topLeftSelection.height)
        var width = handle.movesLeftEdge ? right - (left + delta.deltaX) : right + delta.deltaX - left
        var height = handle.movesTopEdge ? bottom - (top + delta.deltaY) : bottom + delta.deltaY - top

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

        let originX = handle.movesLeftEdge ? right - width : left
        let originY = handle.movesTopEdge ? bottom - height : top
        return try CaptureRect(x: originX, y: originY, width: width, height: height)
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
        let centerX = Double(topLeftSelection.originX) + Double(topLeftSelection.width) / 2
        let centerY = Double(topLeftSelection.originY) + Double(topLeftSelection.height) / 2
        let originX = clamp(
            Int((centerX - Double(resolvedWidth) / 2).rounded()),
            minimum: 0,
            maximum: display.width - resolvedWidth
        )
        let originY = clamp(
            Int((centerY - Double(resolvedHeight) / 2).rounded()),
            minimum: 0,
            maximum: display.height - resolvedHeight
        )

        return try replacingSelection(
            x: originX, y: originY, width: resolvedWidth, height: resolvedHeight)
    }
}
