import Foundation

public struct NormalizedRect: Codable, Equatable, Sendable {
    public static let fullFrame = NormalizedRect(
        uncheckedX: 0,
        y: 0,
        width: 1,
        height: 1
    )

    public let originX: Double
    public let originY: Double
    public let width: Double
    public let height: Double

    public init(x originX: Double, y originY: Double, width: Double, height: Double) throws {
        guard [originX, originY, width, height].allSatisfy(\.isFinite),
            originX >= 0,
            originY >= 0,
            width > 0,
            height > 0,
            originX + width <= 1,
            originY + height <= 1
        else {
            throw ZoomPanModelError.invalidNormalizedRect
        }

        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    private init(uncheckedX xCoordinate: Double, y yCoordinate: Double, width: Double, height: Double) {
        self.originX = xCoordinate
        self.originY = yCoordinate
        self.width = width
        self.height = height
    }

    public var center: NormalizedPoint {
        get throws {
            try NormalizedPoint(x: originX + width / 2, y: originY + height / 2)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

public struct ZoomBlock: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let targetRect: NormalizedRect
    public let zoom: Double
    public let transitionOverride: TimeInterval?

    public init(
        timeRange: TimeRange,
        targetRect: NormalizedRect,
        zoom: Double,
        transitionOverride: TimeInterval? = nil
    ) throws {
        guard zoom.isFinite, (1...3).contains(zoom) else {
            throw ZoomPanModelError.invalidZoom
        }

        if let transitionOverride {
            guard transitionOverride.isFinite, transitionOverride > 0 else {
                throw ZoomPanModelError.invalidTransitionDuration
            }
        }

        self.timeRange = timeRange
        self.targetRect = targetRect
        self.zoom = zoom
        self.transitionOverride = transitionOverride
    }

    public static func validateTimeline(_ blocks: [ZoomBlock]) throws {
        for pair in zip(blocks, blocks.dropFirst()) {
            if pair.1.timeRange.start < pair.0.timeRange.start {
                throw ZoomPanModelError.unsortedBlocks
            }

            if pair.1.timeRange.start < pair.0.timeRange.end {
                throw ZoomPanModelError.overlappingBlocks
            }
        }
    }
}

public struct CameraTransform: Codable, Equatable, Sendable {
    public static let identity = CameraTransform(uncheckedScale: 1, sourceRect: .fullFrame)

    public let scale: Double
    public let sourceRect: NormalizedRect

    public init(scale: Double, sourceRect: NormalizedRect) throws {
        guard scale.isFinite, scale >= 1 else {
            throw ZoomPanModelError.invalidZoom
        }

        self.scale = scale
        self.sourceRect = sourceRect
    }

    private init(uncheckedScale scale: Double, sourceRect: NormalizedRect) {
        self.scale = scale
        self.sourceRect = sourceRect
    }

    public var offsetX: Double {
        sourceRect.originX
    }

    public var offsetY: Double {
        sourceRect.originY
    }
}

public struct CameraPath: Equatable, Sendable {
    public let blocks: [ZoomBlock]
    public let sourceSize: PixelSize

    public init(blocks: [ZoomBlock], sourceSize: PixelSize) throws {
        try ZoomBlock.validateTimeline(blocks)

        self.blocks = blocks
        self.sourceSize = sourceSize
    }

    public func transform(
        at time: TimeInterval,
        cursorTimeline: CursorTimeline? = nil,
        cursorSmoothing: CursorSmoothingLevel = .light
    ) throws -> CameraTransform {
        guard time.isFinite, time >= 0 else {
            throw ZoomPanModelError.invalidTime
        }

        guard let blockIndex = blockIndex(at: time) else {
            return .identity
        }

        let block = blocks[blockIndex]
        let target = try targetTransform(
            for: block,
            at: time,
            cursorTimeline: cursorTimeline,
            cursorSmoothing: cursorSmoothing
        )
        let previous = try adjacentPreviousTransform(before: blockIndex)
        let next = try adjacentNextTransform(after: blockIndex)
        let entryDuration = activeTransitionDuration(
            from: previous ?? .identity,
            to: target,
            override: block.transitionOverride,
            blockDuration: block.timeRange.duration
        )
        let exitDuration = activeTransitionDuration(
            from: target,
            to: next ?? .identity,
            override: block.transitionOverride,
            blockDuration: block.timeRange.duration
        )

        if time < block.timeRange.start + entryDuration {
            return try interpolate(
                from: previous ?? .identity,
                to: target,
                progress: (time - block.timeRange.start) / entryDuration
            )
        }

        if time > block.timeRange.end - exitDuration {
            return try interpolate(
                from: target,
                to: next ?? .identity,
                progress: (time - (block.timeRange.end - exitDuration)) / exitDuration
            )
        }

        return target
    }

    private func blockIndex(at time: TimeInterval) -> Int? {
        blocks.firstIndex { block in
            time >= block.timeRange.start && time <= block.timeRange.end
        }
    }

    private func adjacentPreviousTransform(before index: Int) throws -> CameraTransform? {
        guard index > blocks.startIndex else {
            return nil
        }

        let previous = blocks[blocks.index(before: index)]
        guard previous.timeRange.end == blocks[index].timeRange.start else {
            return nil
        }

        return try transform(for: previous)
    }

    private func adjacentNextTransform(after index: Int) throws -> CameraTransform? {
        let nextIndex = blocks.index(after: index)
        guard nextIndex < blocks.endIndex else {
            return nil
        }

        let next = blocks[nextIndex]
        guard blocks[index].timeRange.end == next.timeRange.start else {
            return nil
        }

        return try transform(for: next)
    }

    private func targetTransform(
        for block: ZoomBlock,
        at time: TimeInterval,
        cursorTimeline: CursorTimeline?,
        cursorSmoothing: CursorSmoothingLevel
    ) throws -> CameraTransform {
        var transform = try transform(for: block)
        guard let cursorTimeline,
            let sample = try CursorPathSmoother.sample(
                at: time,
                from: cursorTimeline.samples,
                level: cursorSmoothing,
                frameSize: sourceSize
            )
        else {
            return transform
        }

        transform = try followedTransform(transform, cursor: sample.position)
        return transform
    }

    private func transform(for block: ZoomBlock) throws -> CameraTransform {
        let center = try block.targetRect.center
        return try transform(scale: block.zoom, centeredAt: center)
    }

    private func followedTransform(
        _ cameraTransform: CameraTransform,
        cursor: CursorPoint
    ) throws -> CameraTransform {
        let normalizedCursor = try NormalizedPoint(
            x: cursor.xCoordinate / Double(sourceSize.width),
            y: cursor.yCoordinate / Double(sourceSize.height)
        )
        let deadZoneWidth = cameraTransform.sourceRect.width * 0.6
        let deadZoneHeight = cameraTransform.sourceRect.height * 0.6
        let deadZoneX =
            cameraTransform.sourceRect.originX + (cameraTransform.sourceRect.width - deadZoneWidth) / 2
        let deadZoneY =
            cameraTransform.sourceRect.originY + (cameraTransform.sourceRect.height - deadZoneHeight) / 2
        var originX = cameraTransform.sourceRect.originX
        var originY = cameraTransform.sourceRect.originY

        if normalizedCursor.xCoordinate < deadZoneX {
            originX -= deadZoneX - normalizedCursor.xCoordinate
        } else if normalizedCursor.xCoordinate > deadZoneX + deadZoneWidth {
            originX += normalizedCursor.xCoordinate - (deadZoneX + deadZoneWidth)
        }

        if normalizedCursor.yCoordinate < deadZoneY {
            originY -= deadZoneY - normalizedCursor.yCoordinate
        } else if normalizedCursor.yCoordinate > deadZoneY + deadZoneHeight {
            originY += normalizedCursor.yCoordinate - (deadZoneY + deadZoneHeight)
        }

        return try transform(scale: cameraTransform.scale, originX: originX, originY: originY)
    }

    private func activeTransitionDuration(
        from start: CameraTransform,
        to end: CameraTransform,
        override: TimeInterval?,
        blockDuration: TimeInterval
    ) -> TimeInterval {
        min(defaultTransitionDuration(from: start, to: end, override: override), blockDuration / 2)
    }

    private func defaultTransitionDuration(
        from start: CameraTransform,
        to end: CameraTransform,
        override: TimeInterval?
    ) -> TimeInterval {
        if let override {
            return override
        }

        let deltaX = end.sourceRect.originX - start.sourceRect.originX
        let deltaY = end.sourceRect.originY - start.sourceRect.originY
        let scaleDistance = abs(end.scale - start.scale) / 2
        let distance = min(1, sqrt(deltaX * deltaX + deltaY * deltaY) + scaleDistance)

        return 0.3 + 0.4 * distance
    }

    private func interpolate(
        from start: CameraTransform,
        to end: CameraTransform,
        progress: Double
    ) throws -> CameraTransform {
        let progress = criticallyDampedProgress(progress)
        let scale = start.scale + (end.scale - start.scale) * progress
        let originX =
            start.sourceRect.originX + (end.sourceRect.originX - start.sourceRect.originX) * progress
        let originY =
            start.sourceRect.originY + (end.sourceRect.originY - start.sourceRect.originY) * progress

        return try transform(scale: scale, originX: originX, originY: originY)
    }

    private func criticallyDampedProgress(_ progress: Double) -> Double {
        guard progress > 0 else {
            return 0
        }

        guard progress < 1 else {
            return 1
        }

        let sharpness = 6.0
        let response = 1 - (1 + sharpness * progress) * exp(-sharpness * progress)
        let endResponse = 1 - (1 + sharpness) * exp(-sharpness)

        return response / endResponse
    }

    private func transform(scale: Double, centeredAt center: NormalizedPoint) throws
        -> CameraTransform {
        let size = 1 / scale
        return try transform(
            scale: scale,
            originX: center.xCoordinate - size / 2,
            originY: center.yCoordinate - size / 2
        )
    }

    private func transform(scale: Double, originX: Double, originY: Double) throws -> CameraTransform {
        let size = 1 / scale
        let clampedX = originX.clamped(to: 0...(1 - size))
        let clampedY = originY.clamped(to: 0...(1 - size))

        return try CameraTransform(
            scale: scale,
            sourceRect: NormalizedRect(
                x: clampedX,
                y: clampedY,
                width: size,
                height: size
            )
        )
    }
}
