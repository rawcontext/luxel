import Foundation

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
            mediaDuration: mediaDuration(
                cursorTimeline: cursorTimeline, keystrokeTimeline: keystrokeTimeline),
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

            guard
                let sample = try CursorPathSmoother.sample(
                    at: click.time,
                    from: timeline.samples,
                    level: .light,
                    frameSize: sourceSize
                )
            else {
                return nil
            }

            return try ZoomInterestPoint(
                time: click.time, position: sample.position, sourceSize: sourceSize, weight: 1)
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

            guard
                let sample = try CursorPathSmoother.sample(
                    at: event.time,
                    from: cursorTimeline.samples,
                    level: .light,
                    frameSize: sourceSize
                )
            else {
                return nil
            }

            return try ZoomInterestPoint(
                time: event.time,
                position: sample.position,
                sourceSize: sourceSize,
                weight: 0.5
            )
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
                try appendDwellPoint(
                    from: dwellStart, through: last, sourceSize: sourceSize, tuning: tuning, to: &points
                )
                dwellStart = sample
            }

            last = sample
        }

        try appendDwellPoint(
            from: dwellStart, through: last, sourceSize: sourceSize, tuning: tuning, to: &points
        )

        return points
    }

    private static func appendDwellPoint(
        from start: CursorSample,
        through end: CursorSample,
        sourceSize: PixelSize,
        tuning: ZoomProposalTuning,
        to points: inout [ZoomInterestPoint]
    ) throws {
        guard end.time - start.time >= tuning.dwellDurationThreshold else {
            return
        }
        points.append(
            try ZoomInterestPoint(
                time: (start.time + end.time) / 2,
                position: start.position,
                sourceSize: sourceSize,
                weight: tuning.minimumClusterWeight
            ))
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
        let minX = cluster.map(\.xCoordinate).min() ?? 0.5
        let maxX = cluster.map(\.xCoordinate).max() ?? 0.5
        let minY = cluster.map(\.yCoordinate).min() ?? 0.5
        let maxY = cluster.map(\.yCoordinate).max() ?? 0.5
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
        let cursorDuration =
            [
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
        let deltaX = (end.xCoordinate - start.xCoordinate) / Double(sourceSize.width)
        let deltaY = (end.yCoordinate - start.yCoordinate) / Double(sourceSize.height)

        return sqrt(deltaX * deltaX + deltaY * deltaY)
    }
}

private struct ZoomInterestPoint: Equatable, Sendable {
    let time: TimeInterval
    let xCoordinate: Double
    let yCoordinate: Double
    let weight: Double

    init(time: TimeInterval, position: CursorPoint, sourceSize: PixelSize, weight: Double) throws {
        guard time.isFinite,
              time >= 0,
              weight.isFinite,
              weight > 0
        else {
            throw ZoomPanModelError.invalidProposalTuning
        }

        self.time = time
        xCoordinate = (position.xCoordinate / Double(sourceSize.width)).clamped(to: 0...1)
        yCoordinate = (position.yCoordinate / Double(sourceSize.height)).clamped(to: 0...1)
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
    case invalidDraftID
    case duplicateDraftID
    case invalidDraftState
    case unknownDraftID
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
