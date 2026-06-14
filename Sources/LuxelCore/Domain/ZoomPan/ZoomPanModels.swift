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

public struct ZoomExportTimeMapper: Equatable, Sendable {
    public let trimRange: TimeRange
    public let speed: PlaybackSpeed

    public init(
        trimRange: TimeRange,
        speed: PlaybackSpeed = .normal
    ) {
        self.trimRange = trimRange
        self.speed = speed
    }

    public func map(_ blocks: [ZoomBlock]) throws -> [ZoomBlock] {
        try blocks.compactMap { block in
            try map(block)
        }
    }

    private func map(_ block: ZoomBlock) throws -> ZoomBlock? {
        let start = max(block.timeRange.start, trimRange.start)
        let end = min(block.timeRange.end, trimRange.end)

        guard end > start else {
            return nil
        }

        return try ZoomBlock(
            timeRange: TimeRange(
                start: (start - trimRange.start) / speed.value,
                end: (end - trimRange.start) / speed.value
            ),
            targetRect: block.targetRect,
            zoom: block.zoom,
            transitionOverride: block.transitionOverride.map { $0 / speed.value }
        )
    }
}

public struct ZoomProposalTuning: Codable, Equatable, Sendable {
    public static let standard = ZoomProposalTuning(
        uncheckedClusterTimeGap: 2.5,
        minimumClusterWeight: 1.5,
        minimumBlockDuration: 1.5,
        temporalPadding: 0.25,
        targetPadding: 0.08,
        minimumZoom: 1.2,
        maximumZoom: 3,
        dwellDurationThreshold: 1.5,
        dwellMovementTolerance: 0.03,
        maxProposals: 40
    )

    public let clusterTimeGap: TimeInterval
    public let minimumClusterWeight: Double
    public let minimumBlockDuration: TimeInterval
    public let temporalPadding: TimeInterval
    public let targetPadding: Double
    public let minimumZoom: Double
    public let maximumZoom: Double
    public let dwellDurationThreshold: TimeInterval
    public let dwellMovementTolerance: Double
    public let maxProposals: Int

    public init(
        clusterTimeGap: TimeInterval = 2.5,
        minimumClusterWeight: Double = 1.5,
        minimumBlockDuration: TimeInterval = 1.5,
        temporalPadding: TimeInterval = 0.25,
        targetPadding: Double = 0.08,
        minimumZoom: Double = 1.2,
        maximumZoom: Double = 3,
        dwellDurationThreshold: TimeInterval = 1.5,
        dwellMovementTolerance: Double = 0.03,
        maxProposals: Int = 40
    ) throws {
        guard clusterTimeGap.isFinite,
              clusterTimeGap > 0,
              minimumClusterWeight.isFinite,
              minimumClusterWeight > 0,
              minimumBlockDuration.isFinite,
              minimumBlockDuration > 0,
              temporalPadding.isFinite,
              temporalPadding >= 0,
              targetPadding.isFinite,
              targetPadding >= 0,
              minimumZoom.isFinite,
              maximumZoom.isFinite,
              minimumZoom >= 1,
              maximumZoom <= 3,
              minimumZoom <= maximumZoom,
              dwellDurationThreshold.isFinite,
              dwellDurationThreshold > 0,
              dwellMovementTolerance.isFinite,
              dwellMovementTolerance >= 0,
              maxProposals > 0 else {
            throw ZoomPanModelError.invalidProposalTuning
        }

        self.init(
            uncheckedClusterTimeGap: clusterTimeGap,
            minimumClusterWeight: minimumClusterWeight,
            minimumBlockDuration: minimumBlockDuration,
            temporalPadding: temporalPadding,
            targetPadding: targetPadding,
            minimumZoom: minimumZoom,
            maximumZoom: maximumZoom,
            dwellDurationThreshold: dwellDurationThreshold,
            dwellMovementTolerance: dwellMovementTolerance,
            maxProposals: maxProposals
        )
    }

    private init(
        uncheckedClusterTimeGap clusterTimeGap: TimeInterval,
        minimumClusterWeight: Double,
        minimumBlockDuration: TimeInterval,
        temporalPadding: TimeInterval,
        targetPadding: Double,
        minimumZoom: Double,
        maximumZoom: Double,
        dwellDurationThreshold: TimeInterval,
        dwellMovementTolerance: Double,
        maxProposals: Int
    ) {
        self.clusterTimeGap = clusterTimeGap
        self.minimumClusterWeight = minimumClusterWeight
        self.minimumBlockDuration = minimumBlockDuration
        self.temporalPadding = temporalPadding
        self.targetPadding = targetPadding
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
        self.dwellDurationThreshold = dwellDurationThreshold
        self.dwellMovementTolerance = dwellMovementTolerance
        self.maxProposals = maxProposals
    }
}

public enum ZoomProposalEngine {
    public static func proposals(
        cursorTimeline: CursorTimeline,
        keystrokeTimeline: KeystrokeTimeline? = nil,
        sourceSize: PixelSize,
        tuning: ZoomProposalTuning = .standard
    ) throws -> [ZoomBlock] {
        var interestPoints = try clickInterestPoints(
            from: cursorTimeline,
            sourceSize: sourceSize
        )
        interestPoints += try keystrokeInterestPoints(
            from: keystrokeTimeline,
            cursorTimeline: cursorTimeline,
            sourceSize: sourceSize
        )

        if interestPoints.isEmpty {
            interestPoints = try dwellInterestPoints(
                from: cursorTimeline,
                sourceSize: sourceSize,
                tuning: tuning
            )
        }

        return try proposedBlocks(
            from: interestPoints.sorted { $0.time < $1.time },
            mediaDuration: mediaDuration(cursorTimeline: cursorTimeline, keystrokeTimeline: keystrokeTimeline),
            tuning: tuning
        )
    }

    private static func clickInterestPoints(
        from timeline: CursorTimeline,
        sourceSize: PixelSize
    ) throws -> [ZoomInterestPoint] {
        try timeline.clicks.compactMap { click in
            guard click.phase == .down else {
                return nil
            }

            guard let sample = try CursorPathSmoother.sample(
                at: click.time,
                from: timeline.samples,
                level: .light,
                frameSize: sourceSize
            ) else {
                return nil
            }

            return try ZoomInterestPoint(time: click.time, position: sample.position, sourceSize: sourceSize, weight: 1)
        }
    }

    private static func keystrokeInterestPoints(
        from keystrokeTimeline: KeystrokeTimeline?,
        cursorTimeline: CursorTimeline,
        sourceSize: PixelSize
    ) throws -> [ZoomInterestPoint] {
        guard let keystrokeTimeline else {
            return []
        }

        return try keystrokeTimeline.eventsOutsidePauses().compactMap { event in
            guard event.kind == .keyDown else {
                return nil
            }

            guard let sample = try CursorPathSmoother.sample(
                at: event.time,
                from: cursorTimeline.samples,
                level: .light,
                frameSize: sourceSize
            ) else {
                return nil
            }

            return try ZoomInterestPoint(time: event.time, position: sample.position, sourceSize: sourceSize, weight: 0.5)
        }
    }

    private static func dwellInterestPoints(
        from timeline: CursorTimeline,
        sourceSize: PixelSize,
        tuning: ZoomProposalTuning
    ) throws -> [ZoomInterestPoint] {
        guard let first = timeline.samples.first else {
            return []
        }

        var dwellStart = first
        var last = first
        var points: [ZoomInterestPoint] = []

        for sample in timeline.samples.dropFirst() {
            if normalizedDistance(from: dwellStart.position, to: sample.position, sourceSize: sourceSize)
                > tuning.dwellMovementTolerance {
                if last.time - dwellStart.time >= tuning.dwellDurationThreshold {
                    points.append(try ZoomInterestPoint(
                        time: (dwellStart.time + last.time) / 2,
                        position: dwellStart.position,
                        sourceSize: sourceSize,
                        weight: tuning.minimumClusterWeight
                    ))
                }

                dwellStart = sample
            }

            last = sample
        }

        if last.time - dwellStart.time >= tuning.dwellDurationThreshold {
            points.append(try ZoomInterestPoint(
                time: (dwellStart.time + last.time) / 2,
                position: dwellStart.position,
                sourceSize: sourceSize,
                weight: tuning.minimumClusterWeight
            ))
        }

        return points
    }

    private static func proposedBlocks(
        from points: [ZoomInterestPoint],
        mediaDuration: TimeInterval,
        tuning: ZoomProposalTuning
    ) throws -> [ZoomBlock] {
        guard !points.isEmpty else {
            return []
        }

        var clusters: [[ZoomInterestPoint]] = []
        var currentCluster: [ZoomInterestPoint] = []

        for point in points {
            if let last = currentCluster.last,
               point.time - last.time > tuning.clusterTimeGap {
                clusters.append(currentCluster)
                currentCluster = []
            }

            currentCluster.append(point)
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return try clusters.compactMap { cluster in
            guard cluster.reduce(0, { $0 + $1.weight }) >= tuning.minimumClusterWeight else {
                return nil
            }

            return try proposedBlock(from: cluster, mediaDuration: mediaDuration, tuning: tuning)
        }
        .prefix(tuning.maxProposals)
        .map { $0 }
    }

    private static func proposedBlock(
        from cluster: [ZoomInterestPoint],
        mediaDuration: TimeInterval,
        tuning: ZoomProposalTuning
    ) throws -> ZoomBlock {
        let start = cluster.map(\.time).min() ?? 0
        let end = cluster.map(\.time).max() ?? start
        let timeRange = try proposedTimeRange(
            start: start,
            end: end,
            mediaDuration: mediaDuration,
            tuning: tuning
        )
        let targetRect = try proposedTargetRect(from: cluster, padding: tuning.targetPadding)
        let side = max(targetRect.width, targetRect.height)
        let zoom = (1 / side).clamped(to: tuning.minimumZoom...tuning.maximumZoom)

        return try ZoomBlock(
            timeRange: timeRange,
            targetRect: targetRect,
            zoom: zoom
        )
    }

    private static func proposedTimeRange(
        start: TimeInterval,
        end: TimeInterval,
        mediaDuration: TimeInterval,
        tuning: ZoomProposalTuning
    ) throws -> TimeRange {
        let paddedStart = max(0, start - tuning.temporalPadding)
        let paddedEnd = end + tuning.temporalPadding
        let center = (paddedStart + paddedEnd) / 2
        let duration = max(tuning.minimumBlockDuration, paddedEnd - paddedStart)
        var rangeStart = max(0, center - duration / 2)
        var rangeEnd = center + duration / 2

        if mediaDuration > 0, rangeEnd > mediaDuration {
            let shift = rangeEnd - mediaDuration
            rangeStart = max(0, rangeStart - shift)
            rangeEnd = mediaDuration
        }

        if rangeEnd <= rangeStart {
            rangeEnd = rangeStart + duration
        }

        return try TimeRange(start: rangeStart, end: rangeEnd)
    }

    private static func proposedTargetRect(
        from cluster: [ZoomInterestPoint],
        padding: Double
    ) throws -> NormalizedRect {
        let minX = cluster.map(\.x).min() ?? 0.5
        let maxX = cluster.map(\.x).max() ?? 0.5
        let minY = cluster.map(\.y).min() ?? 0.5
        let maxY = cluster.map(\.y).max() ?? 0.5
        let centerX = (minX + maxX) / 2
        let centerY = (minY + maxY) / 2
        let side = min(1, max(maxX - minX, maxY - minY) + padding * 2)
        let originX = (centerX - side / 2).clamped(to: 0...(1 - side))
        let originY = (centerY - side / 2).clamped(to: 0...(1 - side))

        return try NormalizedRect(x: originX, y: originY, width: side, height: side)
    }

    private static func mediaDuration(
        cursorTimeline: CursorTimeline,
        keystrokeTimeline: KeystrokeTimeline?
    ) -> TimeInterval {
        let cursorDuration = [
            cursorTimeline.samples.last?.time,
            cursorTimeline.clicks.last?.time,
            cursorTimeline.spotlightToggles.last
        ].compactMap { $0 }.max() ?? 0
        let keystrokeDuration = keystrokeTimeline?.events.last?.time ?? 0

        return max(cursorDuration, keystrokeDuration)
    }

    private static func normalizedDistance(
        from start: CursorPoint,
        to end: CursorPoint,
        sourceSize: PixelSize
    ) -> Double {
        let dx = (end.x - start.x) / Double(sourceSize.width)
        let dy = (end.y - start.y) / Double(sourceSize.height)

        return sqrt(dx * dx + dy * dy)
    }
}

private struct ZoomInterestPoint: Equatable, Sendable {
    let time: TimeInterval
    let x: Double
    let y: Double
    let weight: Double

    init(time: TimeInterval, position: CursorPoint, sourceSize: PixelSize, weight: Double) throws {
        guard time.isFinite,
              time >= 0,
              weight.isFinite,
              weight > 0 else {
            throw ZoomPanModelError.invalidProposalTuning
        }

        self.time = time
        x = (position.x / Double(sourceSize.width)).clamped(to: 0...1)
        y = (position.y / Double(sourceSize.height)).clamped(to: 0...1)
        self.weight = weight
    }
}

public enum ZoomPanModelError: Error, Equatable {
    case invalidNormalizedRect
    case invalidZoom
    case invalidTransitionDuration
    case unsortedBlocks
    case overlappingBlocks
    case invalidTime
    case invalidProposalTuning
}

private extension Double {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
