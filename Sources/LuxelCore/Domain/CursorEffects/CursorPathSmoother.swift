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
              time < last.time else {
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
              isRenderable(upper, frameSize: frameSize) else {
            return nil
        }

        let progress = (time - lower.time) / (upper.time - lower.time)
        let position = try position(
            between: lowerIndex,
            and: upperIndex,
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
        between lowerIndex: Int,
        and upperIndex: Int,
        in samples: [CursorSample],
        progress: Double,
        level: CursorSmoothingLevel,
        frameSize: PixelSize?
    ) throws -> CursorPoint {
        let lower = samples[lowerIndex]
        let upper = samples[upperIndex]

        switch level {
        case .off:
            return try interpolatedPoint(from: lower.position, to: upper.position, progress: progress)
        case .light, .medium:
            let previous = renderableNeighbor(before: lowerIndex, in: samples, frameSize: frameSize) ?? lower
            let next = renderableNeighbor(after: upperIndex, in: samples, frameSize: frameSize) ?? upper
            let tension = level == .light ? 0.5 : 0
            let position = try catmullRomPoint(
                previous.position,
                lower.position,
                upper.position,
                next.position,
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

        return sample.position.x >= 0
            && sample.position.y >= 0
            && sample.position.x < Double(frameSize.width)
            && sample.position.y < Double(frameSize.height)
    }

    private static func interpolatedPoint(
        from start: CursorPoint,
        to end: CursorPoint,
        progress: Double
    ) throws -> CursorPoint {
        try CursorPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    private static func catmullRomPoint(
        _ p0: CursorPoint,
        _ p1: CursorPoint,
        _ p2: CursorPoint,
        _ p3: CursorPoint,
        progress: Double,
        tension: Double
    ) throws -> CursorPoint {
        let t2 = progress * progress
        let t3 = t2 * progress
        let tangentScale = (1 - tension) / 2
        let m1x = (p2.x - p0.x) * tangentScale
        let m1y = (p2.y - p0.y) * tangentScale
        let m2x = (p3.x - p1.x) * tangentScale
        let m2y = (p3.y - p1.y) * tangentScale
        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + progress
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        return try CursorPoint(
            x: h00 * p1.x + h10 * m1x + h01 * p2.x + h11 * m2x,
            y: h00 * p1.y + h10 * m1y + h01 * p2.y + h11 * m2y
        )
    }

    private static func clamped(
        _ point: CursorPoint,
        between start: CursorPoint,
        and end: CursorPoint
    ) throws -> CursorPoint {
        try CursorPoint(
            x: point.x.clamped(to: min(start.x, end.x)...max(start.x, end.x)),
            y: point.y.clamped(to: min(start.y, end.y)...max(start.y, end.y))
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
