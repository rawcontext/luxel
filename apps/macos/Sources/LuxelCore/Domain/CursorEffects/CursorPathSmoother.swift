import Foundation

public enum CursorPathSmoother {
    public static func samples(
        at times: [TimeInterval],
        from samples: [CursorSample],
        level: CursorSmoothingLevel,
        frameSize: PixelSize? = nil
    ) throws -> [CursorSample] {
        try times.compactMap { time in
            try sample(at: time, from: samples, level: level, frameSize: frameSize)
        }
    }

    public static func sample(
        at time: TimeInterval,
        from samples: [CursorSample],
        level: CursorSmoothingLevel,
        frameSize: PixelSize? = nil
    ) throws -> CursorSample? {
        guard time.isFinite, time >= 0 else {
            throw CursorEffectModelError.invalidTime
        }

        guard !samples.isEmpty else {
            return nil
        }

        try validateSorted(samples)

        if let exactSample = samples.first(where: { $0.time == time }) {
            return isRenderable(exactSample, frameSize: frameSize) ? exactSample : nil
        }

        guard let first = samples.first,
            let last = samples.last,
            time > first.time,
            time < last.time
        else {
            return nil
        }

        guard let upperIndex = samples.firstIndex(where: { $0.time > time }) else {
            return nil
        }

        let lowerIndex = samples.index(before: upperIndex)
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]
        guard lower.time < upper.time,
            isRenderable(lower, frameSize: frameSize),
            isRenderable(upper, frameSize: frameSize)
        else {
            return nil
        }

        let progress = (time - lower.time) / (upper.time - lower.time)
        let position = try position(
            between: lowerIndex...upperIndex,
            in: samples,
            progress: progress,
            level: level,
            frameSize: frameSize
        )

        return try CursorSample(
            time: time,
            position: position,
            cursorImageID: lower.cursorImageID
        )
    }

    private static func position(
        between indices: ClosedRange<Int>,
        in samples: [CursorSample],
        progress: Double,
        level: CursorSmoothingLevel,
        frameSize: PixelSize?
    ) throws -> CursorPoint {
        let lowerIndex = indices.lowerBound
        let upperIndex = indices.upperBound
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]

        switch level {
        case .off:
            return try interpolatedPoint(from: lower.position, to: upper.position, progress: progress)
        case .light, .medium:
            let previous =
                renderableNeighbor(before: lowerIndex, in: samples, frameSize: frameSize) ?? lower
            let next = renderableNeighbor(after: upperIndex, in: samples, frameSize: frameSize) ?? upper
            let tension = level == .light ? 0.5 : 0
            let position = try catmullRomPoint(
                segment: CatmullRomSegment(
                    previous: previous.position,
                    start: lower.position,
                    end: upper.position,
                    next: next.position
                ),
                progress: progress,
                tension: tension
            )
            return try clamped(position, between: lower.position, and: upper.position)
        }
    }

    private static func validateSorted(_ samples: [CursorSample]) throws {
        for pair in zip(samples, samples.dropFirst()) where pair.1.time < pair.0.time {
            throw CursorEffectModelError.unsortedEvents
        }
    }

    private static func renderableNeighbor(
        before index: Int,
        in samples: [CursorSample],
        frameSize: PixelSize?
    ) -> CursorSample? {
        guard index > samples.startIndex else {
            return nil
        }

        let neighbor = samples[samples.index(before: index)]
        return isRenderable(neighbor, frameSize: frameSize) ? neighbor : nil
    }

    private static func renderableNeighbor(
        after index: Int,
        in samples: [CursorSample],
        frameSize: PixelSize?
    ) -> CursorSample? {
        let neighborIndex = samples.index(after: index)
        guard neighborIndex < samples.endIndex else {
            return nil
        }

        let neighbor = samples[neighborIndex]
        return isRenderable(neighbor, frameSize: frameSize) ? neighbor : nil
    }

    private static func isRenderable(_ sample: CursorSample, frameSize: PixelSize?) -> Bool {
        guard let frameSize else {
            return true
        }

        return sample.position.xCoordinate >= 0
            && sample.position.yCoordinate >= 0
            && sample.position.xCoordinate < Double(frameSize.width)
            && sample.position.yCoordinate < Double(frameSize.height)
    }

    private static func interpolatedPoint(
        from start: CursorPoint,
        to end: CursorPoint,
        progress: Double
    ) throws -> CursorPoint {
        return try CursorPoint(
            x: start.xCoordinate + (end.xCoordinate - start.xCoordinate) * progress,
            y: start.yCoordinate + (end.yCoordinate - start.yCoordinate) * progress
        )
    }

    private static func catmullRomPoint(
        segment: CatmullRomSegment,
        progress: Double,
        tension: Double
    ) throws -> CursorPoint {
        let previousPoint = segment.previous
        let startPoint = segment.start
        let endPoint = segment.end
        let nextPoint = segment.next
        let squaredProgress = progress * progress
        let cubedProgress = squaredProgress * progress
        let tangentScale = (1 - tension) / 2
        let m1x = (endPoint.xCoordinate - previousPoint.xCoordinate) * tangentScale
        let m1y = (endPoint.yCoordinate - previousPoint.yCoordinate) * tangentScale
        let m2x = (nextPoint.xCoordinate - startPoint.xCoordinate) * tangentScale
        let m2y = (nextPoint.yCoordinate - startPoint.yCoordinate) * tangentScale
        let h00 = 2 * cubedProgress - 3 * squaredProgress + 1
        let h10 = cubedProgress - 2 * squaredProgress + progress
        let h01 = -2 * cubedProgress + 3 * squaredProgress
        let h11 = cubedProgress - squaredProgress

        return try CursorPoint(
            x: h00 * startPoint.xCoordinate + h10 * m1x + h01 * endPoint.xCoordinate + h11 * m2x,
            y: h00 * startPoint.yCoordinate + h10 * m1y + h01 * endPoint.yCoordinate + h11 * m2y
        )
    }

    private static func clamped(
        _ point: CursorPoint,
        between start: CursorPoint,
        and end: CursorPoint
    ) throws -> CursorPoint {
        let xRange = min(start.xCoordinate, end.xCoordinate)...max(start.xCoordinate, end.xCoordinate)
        let yRange = min(start.yCoordinate, end.yCoordinate)...max(start.yCoordinate, end.yCoordinate)
        return try CursorPoint(
            x: point.xCoordinate.clamped(to: xRange),
            y: point.yCoordinate.clamped(to: yRange)
        )
    }
}

private struct CatmullRomSegment {
    let previous: CursorPoint
    let start: CursorPoint
    let end: CursorPoint
    let next: CursorPoint
}

extension Double {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
