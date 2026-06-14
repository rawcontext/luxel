import Foundation

public struct NormalizedRect: Codable, Equatable, Sendable {
    public static let fullFrame = try! NormalizedRect(x: 0, y: 0, width: 1, height: 1)

    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard [x, y, width, height].allSatisfy(\.isFinite),
              x >= 0,
              y >= 0,
              width > 0,
              height > 0,
              x + width <= 1,
              y + height <= 1 else {
            throw ZoomPanModelError.invalidNormalizedRect
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var center: NormalizedPoint {
        get throws {
            try NormalizedPoint(x: x + width / 2, y: y + height / 2)
        }
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
}

public struct CameraTransform: Codable, Equatable, Sendable {
    public static let identity = try! CameraTransform(scale: 1, sourceRect: .fullFrame)

    public let scale: Double
    public let sourceRect: NormalizedRect

    public init(scale: Double, sourceRect: NormalizedRect) throws {
        guard scale.isFinite, scale >= 1 else {
            throw ZoomPanModelError.invalidZoom
        }

        self.scale = scale
        self.sourceRect = sourceRect
    }

    public var offsetX: Double {
        sourceRect.x
    }

    public var offsetY: Double {
        sourceRect.y
    }
}

public struct CameraPath: Equatable, Sendable {
    public let blocks: [ZoomBlock]
    public let sourceSize: PixelSize

    public init(blocks: [ZoomBlock], sourceSize: PixelSize) throws {
        try Self.validate(blocks)

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
        let previous = adjacentPreviousTransform(before: blockIndex)
        let next = adjacentNextTransform(after: blockIndex)
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

    private static func validate(_ blocks: [ZoomBlock]) throws {
        for pair in zip(blocks, blocks.dropFirst()) {
            if pair.1.timeRange.start < pair.0.timeRange.start {
                throw ZoomPanModelError.unsortedBlocks
            }

            if pair.1.timeRange.start < pair.0.timeRange.end {
                throw ZoomPanModelError.overlappingBlocks
            }
        }
    }

    private func blockIndex(at time: TimeInterval) -> Int? {
        blocks.firstIndex { block in
            time >= block.timeRange.start && time <= block.timeRange.end
        }
    }

    private func adjacentPreviousTransform(before index: Int) -> CameraTransform? {
        guard index > blocks.startIndex else {
            return nil
        }

        let previous = blocks[blocks.index(before: index)]
        guard previous.timeRange.end == blocks[index].timeRange.start else {
            return nil
        }

        return transform(for: previous)
    }

    private func adjacentNextTransform(after index: Int) -> CameraTransform? {
        let nextIndex = blocks.index(after: index)
        guard nextIndex < blocks.endIndex else {
            return nil
        }

        let next = blocks[nextIndex]
        guard blocks[index].timeRange.end == next.timeRange.start else {
            return nil
        }

        return transform(for: next)
    }

    private func targetTransform(
        for block: ZoomBlock,
        at time: TimeInterval,
        cursorTimeline: CursorTimeline?,
        cursorSmoothing: CursorSmoothingLevel
    ) throws -> CameraTransform {
        var transform = transform(for: block)
        guard let cursorTimeline,
              let sample = try CursorPathSmoother.sample(
                at: time,
                from: cursorTimeline.samples,
                level: cursorSmoothing,
                frameSize: sourceSize
              ) else {
            return transform
        }

        transform = try followedTransform(transform, cursor: sample.position)
        return transform
    }

    private func transform(for block: ZoomBlock) -> CameraTransform {
        let center = try! block.targetRect.center
        return try! transform(scale: block.zoom, centeredAt: center)
    }

    private func followedTransform(
        _ cameraTransform: CameraTransform,
        cursor: CursorPoint
    ) throws -> CameraTransform {
        let normalizedCursor = try NormalizedPoint(
            x: cursor.x / Double(sourceSize.width),
            y: cursor.y / Double(sourceSize.height)
        )
        let deadZoneWidth = cameraTransform.sourceRect.width * 0.6
        let deadZoneHeight = cameraTransform.sourceRect.height * 0.6
        let deadZoneX = cameraTransform.sourceRect.x + (cameraTransform.sourceRect.width - deadZoneWidth) / 2
        let deadZoneY = cameraTransform.sourceRect.y + (cameraTransform.sourceRect.height - deadZoneHeight) / 2
        var originX = cameraTransform.sourceRect.x
        var originY = cameraTransform.sourceRect.y

        if normalizedCursor.x < deadZoneX {
            originX -= deadZoneX - normalizedCursor.x
        } else if normalizedCursor.x > deadZoneX + deadZoneWidth {
            originX += normalizedCursor.x - (deadZoneX + deadZoneWidth)
        }

        if normalizedCursor.y < deadZoneY {
            originY -= deadZoneY - normalizedCursor.y
        } else if normalizedCursor.y > deadZoneY + deadZoneHeight {
            originY += normalizedCursor.y - (deadZoneY + deadZoneHeight)
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

        let dx = end.sourceRect.x - start.sourceRect.x
        let dy = end.sourceRect.y - start.sourceRect.y
        let scaleDistance = abs(end.scale - start.scale) / 2
        let distance = min(1, sqrt(dx * dx + dy * dy) + scaleDistance)

        return 0.3 + 0.4 * distance
    }

    private func interpolate(
        from start: CameraTransform,
        to end: CameraTransform,
        progress: Double
    ) throws -> CameraTransform {
        let progress = criticallyDampedProgress(progress)
        let scale = start.scale + (end.scale - start.scale) * progress
        let originX = start.sourceRect.x + (end.sourceRect.x - start.sourceRect.x) * progress
        let originY = start.sourceRect.y + (end.sourceRect.y - start.sourceRect.y) * progress

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

    private func transform(scale: Double, centeredAt center: NormalizedPoint) throws -> CameraTransform {
        let size = 1 / scale
        return try transform(
            scale: scale,
            originX: center.x - size / 2,
            originY: center.y - size / 2
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

public enum ZoomPanModelError: Error, Equatable {
    case invalidNormalizedRect
    case invalidZoom
    case invalidTransitionDuration
    case unsortedBlocks
    case overlappingBlocks
    case invalidTime
}

private extension Double {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
