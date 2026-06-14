import Foundation

public struct ReplayBufferConfiguration: Codable, Equatable, Sendable {
    public let bufferLength: TimeInterval
    public let source: ReplayBufferSource
    public let frameRate: FrameRate
    public let includeSystemAudio: Bool
    public let quality: ExportQuality

    public init(
        bufferLength: TimeInterval,
        source: ReplayBufferSource,
        frameRate: FrameRate,
        includeSystemAudio: Bool = false,
        quality: ExportQuality = .balanced
    ) throws {
        guard bufferLength.isFinite, (10...600).contains(bufferLength) else {
            throw ReplayBufferModelError.invalidBufferLength
        }

        guard quality.isAvailable(for: .hevc) else {
            throw ReplayBufferModelError.invalidQuality
        }

        self.bufferLength = bufferLength
        self.source = source
        self.frameRate = frameRate
        self.includeSystemAudio = includeSystemAudio
        self.quality = quality
    }
}

public enum ReplayBufferSource: Codable, Equatable, Sendable {
    case display(DisplayID)
    case displayWithCursor
}

public enum ReplayBufferState: Equatable, Sendable {
    case disarmed
    case buffering(since: Date)
    case paused(reason: ReplayBufferPauseReason)
    case clipping
}

public enum ReplayBufferPauseReason: String, Codable, Equatable, Sendable {
    case user
    case recordingActive
    case displaySleep
    case locked
    case battery
    case displayChanged
}

public struct ReplayBufferSegment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let start: TimeInterval
    public let duration: TimeInterval

    public init(id: String, start: TimeInterval, duration: TimeInterval) throws {
        guard start.isFinite, start >= 0 else {
            throw ReplayBufferModelError.invalidSegmentStart
        }

        guard duration.isFinite, duration > 0 else {
            throw ReplayBufferModelError.invalidSegmentDuration
        }

        self.id = id
        self.start = start
        self.duration = duration
    }

    public var end: TimeInterval {
        start + duration
    }

    public var timeRange: TimeRange {
        get throws {
            try TimeRange(start: start, end: end)
        }
    }
}

public struct SegmentLedger: Codable, Equatable, Sendable {
    public let bufferLength: TimeInterval
    public let segments: [ReplayBufferSegment]

    public init(
        bufferLength: TimeInterval,
        segments: [ReplayBufferSegment] = []
    ) throws {
        guard bufferLength.isFinite, bufferLength > 0 else {
            throw ReplayBufferModelError.invalidBufferLength
        }

        try Self.validateSegmentOrder(segments)

        self.bufferLength = bufferLength
        self.segments = Self.evictSegments(segments, bufferLength: bufferLength)
    }

    public func appending(_ segment: ReplayBufferSegment) throws -> SegmentLedger {
        if let lastSegment = segments.last, segment.start < lastSegment.end {
            throw ReplayBufferModelError.invalidSegmentOrder
        }

        return try SegmentLedger(bufferLength: bufferLength, segments: segments + [segment])
    }

    public func segmentsCovering(lastSeconds: TimeInterval) throws -> ReplayBufferClipCoverage {
        guard lastSeconds.isFinite, lastSeconds > 0 else {
            throw ReplayBufferModelError.invalidClipDuration
        }

        guard let latestEnd = segments.last?.end else {
            return ReplayBufferClipCoverage(
                segments: [],
                requestedDuration: lastSeconds,
                coveredDuration: 0,
                trimStartOffset: nil,
                isShort: true
            )
        }

        let requestedStart = max(0, latestEnd - lastSeconds)
        let selectedSegments = segments.filter { $0.end > requestedStart }
        guard let firstSelectedSegment = selectedSegments.first,
              let lastSelectedSegment = selectedSegments.last else {
            return ReplayBufferClipCoverage(
                segments: [],
                requestedDuration: lastSeconds,
                coveredDuration: 0,
                trimStartOffset: nil,
                isShort: true
            )
        }

        let trimStartOffset = max(0, requestedStart - firstSelectedSegment.start)
        let coveredDuration = lastSelectedSegment.end - firstSelectedSegment.start - trimStartOffset
        return ReplayBufferClipCoverage(
            segments: selectedSegments,
            requestedDuration: lastSeconds,
            coveredDuration: coveredDuration,
            trimStartOffset: trimStartOffset,
            isShort: coveredDuration < lastSeconds
        )
    }

    public func exactTrimStart(for lastSeconds: TimeInterval) throws -> TimeInterval? {
        try segmentsCovering(lastSeconds: lastSeconds).trimStartOffset
    }

    private static func validateSegmentOrder(_ segments: [ReplayBufferSegment]) throws {
        for pair in zip(segments, segments.dropFirst()) where pair.1.start < pair.0.end {
            throw ReplayBufferModelError.invalidSegmentOrder
        }
    }

    private static func evictSegments(
        _ segments: [ReplayBufferSegment],
        bufferLength: TimeInterval
    ) -> [ReplayBufferSegment] {
        guard let latestEnd = segments.last?.end else {
            return segments
        }

        let cutoff = max(0, latestEnd - bufferLength)
        guard let firstOverlapIndex = segments.firstIndex(where: { $0.end > cutoff }) else {
            return Array(segments.suffix(1))
        }

        let firstIndexToKeep = firstOverlapIndex == segments.startIndex
            ? firstOverlapIndex
            : segments.index(before: firstOverlapIndex)
        return Array(segments[firstIndexToKeep...])
    }
}

public struct ReplayBufferClipCoverage: Equatable, Sendable {
    public let segments: [ReplayBufferSegment]
    public let requestedDuration: TimeInterval
    public let coveredDuration: TimeInterval
    public let trimStartOffset: TimeInterval?
    public let isShort: Bool

    public init(
        segments: [ReplayBufferSegment],
        requestedDuration: TimeInterval,
        coveredDuration: TimeInterval,
        trimStartOffset: TimeInterval?,
        isShort: Bool
    ) {
        self.segments = segments
        self.requestedDuration = requestedDuration
        self.coveredDuration = coveredDuration
        self.trimStartOffset = trimStartOffset
        self.isShort = isShort
    }
}

public enum ReplayBufferModelError: Error, Equatable {
    case invalidBufferLength
    case invalidQuality
    case invalidSegmentStart
    case invalidSegmentDuration
    case invalidSegmentOrder
    case invalidClipDuration
}
