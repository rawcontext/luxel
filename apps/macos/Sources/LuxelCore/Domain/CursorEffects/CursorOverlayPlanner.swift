import Foundation

public struct CursorOverlayFramePlan: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let cursor: CursorOverlayCursorPlan?
    public let clickEffects: [CursorClickEffectPlan]
    public let spotlight: CursorSpotlightPlan?

    public init(
        time: TimeInterval,
        cursor: CursorOverlayCursorPlan? = nil,
        clickEffects: [CursorClickEffectPlan] = [],
        spotlight: CursorSpotlightPlan? = nil
    ) {
        self.time = time
        self.cursor = cursor
        self.clickEffects = clickEffects
        self.spotlight = spotlight
    }

    public var isEmpty: Bool {
        cursor == nil && clickEffects.isEmpty && spotlight == nil
    }
}

public struct CursorOverlayCursorPlan: Codable, Equatable, Sendable {
    public let image: CursorImageAsset
    public let hotspotPosition: CursorPoint
    public let imageOrigin: CursorPoint
    public let sizeMultiplier: Double

    public init(
        image: CursorImageAsset,
        hotspotPosition: CursorPoint,
        imageOrigin: CursorPoint,
        sizeMultiplier: Double
    ) {
        self.image = image
        self.hotspotPosition = hotspotPosition
        self.imageOrigin = imageOrigin
        self.sizeMultiplier = sizeMultiplier
    }
}

public struct CursorClickEffectPlan: Codable, Equatable, Sendable {
    public let event: CursorClickEvent
    public let timeRange: TimeRange
    public let center: CursorPoint
    public let style: CursorClickStyle
    public let color: CursorRGBAColor
    public let sizeMultiplier: Double
    public let progress: Double

    public init(
        event: CursorClickEvent,
        timeRange: TimeRange,
        center: CursorPoint,
        style: CursorClickStyle,
        color: CursorRGBAColor,
        sizeMultiplier: Double,
        progress: Double
    ) {
        self.event = event
        self.timeRange = timeRange
        self.center = center
        self.style = style
        self.color = color
        self.sizeMultiplier = sizeMultiplier
        self.progress = progress
    }
}

public struct CursorSpotlightPlan: Codable, Equatable, Sendable {
    public let center: CursorPoint
    public let options: CursorSpotlightOptions

    public init(center: CursorPoint, options: CursorSpotlightOptions) {
        self.center = center
        self.options = options
    }
}

public enum CursorOverlayPlanner {
    public static func plan(
        at time: TimeInterval,
        timeline: CursorTimeline,
        options: CursorRenderOptions,
        frameSize: PixelSize,
        recordingDuration: TimeInterval
    ) throws -> CursorOverlayFramePlan {
        guard recordingDuration.isFinite, recordingDuration >= 0 else {
            throw CursorEffectModelError.invalidRecordingDuration
        }

        guard time.isFinite, time >= 0, time <= recordingDuration else {
            throw CursorEffectModelError.invalidTime
        }

        let imageLookup = try cursorImageLookup(from: timeline.cursorImages)
        let currentSample = try CursorPathSmoother.sample(
            at: time,
            from: timeline.samples,
            level: options.smoothing,
            frameSize: frameSize
        )
        let cursor = try cursorPlan(
            for: currentSample,
            imageLookup: imageLookup,
            options: options
        )
        let clickEffects = try clickEffectPlans(
            at: time,
            timeline: timeline,
            imageLookup: imageLookup,
            options: options,
            frameSize: frameSize
        )
        let spotlight = try spotlightPlan(
            at: time,
            sample: currentSample,
            timeline: timeline,
            options: options,
            recordingDuration: recordingDuration
        )

        return CursorOverlayFramePlan(
            time: time,
            cursor: cursor,
            clickEffects: clickEffects,
            spotlight: spotlight
        )
    }

    private static func cursorPlan(
        for sample: CursorSample?,
        imageLookup: [String: CursorImageAsset],
        options: CursorRenderOptions
    ) throws -> CursorOverlayCursorPlan? {
        guard options.isVisible, let sample else {
            return nil
        }

        guard let image = imageLookup[sample.cursorImageID] else {
            throw CursorEffectModelError.missingCursorImage
        }

        let hotspotOffset = try CursorPoint(
            x: image.hotspot.xCoordinate * options.sizeMultiplier,
            y: image.hotspot.yCoordinate * options.sizeMultiplier
        )
        let origin = try CursorPoint(
            x: sample.position.xCoordinate - hotspotOffset.xCoordinate,
            y: sample.position.yCoordinate - hotspotOffset.yCoordinate
        )

        return CursorOverlayCursorPlan(
            image: image,
            hotspotPosition: sample.position,
            imageOrigin: origin,
            sizeMultiplier: options.sizeMultiplier
        )
    }

    private static func cursorImageLookup(
        from images: [CursorImageAsset]
    ) throws -> [String: CursorImageAsset] {
        var imageLookup: [String: CursorImageAsset] = [:]
        for image in images {
            guard imageLookup[image.id] == nil else {
                throw CursorEffectModelError.duplicateCursorImageID
            }

            imageLookup[image.id] = image
        }

        return imageLookup
    }

    private static func clickEffectPlans(
        at time: TimeInterval,
        timeline: CursorTimeline,
        imageLookup: [String: CursorImageAsset],
        options: CursorRenderOptions,
        frameSize: PixelSize
    ) throws -> [CursorClickEffectPlan] {
        guard options.clickStyle != .none, options.clickDuration > 0 else {
            return []
        }

        return try timeline.clicks.compactMap { event in
            guard event.phase == .down else {
                return nil
            }

            let endTime = event.time + options.clickDuration
            guard time >= event.time, time < endTime else {
                return nil
            }

            let sample = try CursorPathSmoother.sample(
                at: event.time,
                from: timeline.samples,
                level: options.smoothing,
                frameSize: frameSize
            )
            guard let sample else {
                return nil
            }

            guard imageLookup[sample.cursorImageID] != nil else {
                throw CursorEffectModelError.missingCursorImage
            }

            return CursorClickEffectPlan(
                event: event,
                timeRange: try TimeRange(start: event.time, end: endTime),
                center: sample.position,
                style: options.clickStyle,
                color: options.clickColor,
                sizeMultiplier: options.clickSize,
                progress: (time - event.time) / options.clickDuration
            )
        }
    }

    private static func spotlightPlan(
        at time: TimeInterval,
        sample: CursorSample?,
        timeline: CursorTimeline,
        options: CursorRenderOptions,
        recordingDuration: TimeInterval
    ) throws -> CursorSpotlightPlan? {
        guard let options = options.spotlight,
              let sample,
              try spotlightIsActive(at: time, timeline: timeline, recordingDuration: recordingDuration)
        else {
            return nil
        }

        return CursorSpotlightPlan(center: sample.position, options: options)
    }

    private static func spotlightIsActive(
        at time: TimeInterval,
        timeline: CursorTimeline,
        recordingDuration: TimeInterval
    ) throws -> Bool {
        guard !timeline.spotlightToggles.isEmpty else {
            return time <= recordingDuration
        }

        let intervals = try SpotlightIntervalResolver.intervals(
            from: timeline.spotlightToggles,
            recordingDuration: recordingDuration
        )

        return intervals.contains { interval in
            time >= interval.timeRange.start && time < interval.timeRange.end
        }
    }
}
