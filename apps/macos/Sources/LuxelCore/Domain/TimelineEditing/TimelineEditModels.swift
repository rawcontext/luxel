import Foundation

public enum TimelineCutKind: String, Codable, Equatable, Sendable {
    case transcriptSentence
    case silence
    case fillerWord
}

public struct TimelineCut: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let sourceRange: TimeRange
    public let kind: TimelineCutKind
    public let transcriptSpanIDs: [String]

    public init(
        id: String,
        sourceRange: TimeRange,
        kind: TimelineCutKind,
        transcriptSpanIDs: [String] = []
    ) throws {
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty,
            sourceRange.start.isFinite,
            sourceRange.end.isFinite
        else {
            throw TimelineEditingError.invalidCut
        }

        self.id = normalizedID
        self.sourceRange = sourceRange
        self.kind = kind
        self.transcriptSpanIDs = Self.unique(transcriptSpanIDs)
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

public struct TimelineEditPlan: Codable, Equatable, Sendable {
    public static let empty = TimelineEditPlan(uncheckedCuts: [])

    public let cuts: [TimelineCut]

    public init(cuts: [TimelineCut]) throws {
        var seenIDs: Set<String> = []
        guard cuts.allSatisfy({ seenIDs.insert($0.id).inserted }) else {
            throw TimelineEditingError.duplicateCutID
        }

        self.cuts = try Self.normalized(cuts)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(cuts: container.decode([TimelineCut].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(cuts)
    }

    public func clipped(to trimRange: TimeRange) throws -> TimelineEditPlan {
        try TimelineEditPlan(
            cuts: cuts.compactMap { cut in
                let start = max(cut.sourceRange.start, trimRange.start)
                let end = min(cut.sourceRange.end, trimRange.end)
                guard end > start else {
                    return nil
                }

                return try TimelineCut(
                    id: cut.id,
                    sourceRange: TimeRange(start: start, end: end),
                    kind: cut.kind,
                    transcriptSpanIDs: cut.transcriptSpanIDs
                )
            }
        )
    }

    public func inserting(
        _ cut: TimelineCut,
        within trimRange: TimeRange,
        minimumRetainedDuration: TimeInterval
    ) throws -> TimelineEditPlan? {
        let start = max(cut.sourceRange.start, trimRange.start)
        let end = min(cut.sourceRange.end, trimRange.end)
        guard end > start else {
            return nil
        }

        let clippedCut = try TimelineCut(
            id: cut.id,
            sourceRange: TimeRange(start: start, end: end),
            kind: cut.kind,
            transcriptSpanIDs: cut.transcriptSpanIDs
        )
        let updated = try TimelineEditPlan(cuts: cuts + [clippedCut])
        guard updated != self else {
            return nil
        }

        let mapper = EditedTimelineMapper(
            trimRange: trimRange,
            editPlan: updated,
            speed: .normal
        )
        guard let retainedDuration = try? mapper.unscaledOutputDuration,
            retainedDuration >= minimumRetainedDuration
        else {
            throw TimelineEditingError.insufficientRetainedDuration
        }

        return updated
    }

    public func removes(_ range: TimeRange) -> Bool {
        cuts.contains {
            $0.sourceRange.start < range.end && range.start < $0.sourceRange.end
        }
    }

    private init(uncheckedCuts: [TimelineCut]) {
        cuts = uncheckedCuts
    }

    private static func normalized(_ cuts: [TimelineCut]) throws -> [TimelineCut] {
        let sorted = cuts.sorted {
            if $0.sourceRange.start == $1.sourceRange.start {
                return $0.sourceRange.end < $1.sourceRange.end
            }
            return $0.sourceRange.start < $1.sourceRange.start
        }
        guard var pending = sorted.first else {
            return []
        }

        var normalized: [TimelineCut] = []
        for cut in sorted.dropFirst() {
            guard cut.sourceRange.start <= pending.sourceRange.end else {
                normalized.append(pending)
                pending = cut
                continue
            }

            pending = try TimelineCut(
                id: pending.id,
                sourceRange: TimeRange(
                    start: pending.sourceRange.start,
                    end: max(pending.sourceRange.end, cut.sourceRange.end)
                ),
                kind: pending.kind,
                transcriptSpanIDs: pending.transcriptSpanIDs + cut.transcriptSpanIDs
            )
        }
        normalized.append(pending)
        return normalized
    }
}

public struct SourceMediaSegment: Codable, Equatable, Sendable {
    public let sourceRange: TimeRange
    public let outputStart: TimeInterval

    public init(sourceRange: TimeRange, outputStart: TimeInterval) {
        self.sourceRange = sourceRange
        self.outputStart = outputStart
    }
}

public struct EditedTimelineMapper: Equatable, Sendable {
    public let trimRange: TimeRange
    public let editPlan: TimelineEditPlan
    public let speed: PlaybackSpeed

    public init(
        trimRange: TimeRange,
        editPlan: TimelineEditPlan = .empty,
        speed: PlaybackSpeed = .normal
    ) {
        self.trimRange = trimRange
        self.editPlan = editPlan
        self.speed = speed
    }

    public var sourceSegments: [SourceMediaSegment] {
        get throws {
            let effectivePlan = try editPlan.clipped(to: trimRange)
            var segments: [SourceMediaSegment] = []
            var sourceStart = trimRange.start
            var outputStart: TimeInterval = 0

            for cut in effectivePlan.cuts {
                if cut.sourceRange.start > sourceStart {
                    let range = try TimeRange(start: sourceStart, end: cut.sourceRange.start)
                    segments.append(SourceMediaSegment(sourceRange: range, outputStart: outputStart))
                    outputStart += range.duration
                }
                sourceStart = max(sourceStart, cut.sourceRange.end)
            }

            if sourceStart < trimRange.end {
                let range = try TimeRange(start: sourceStart, end: trimRange.end)
                segments.append(SourceMediaSegment(sourceRange: range, outputStart: outputStart))
            }

            guard !segments.isEmpty else {
                throw TimelineEditingError.noRetainedMedia
            }
            return segments
        }
    }

    public var unscaledOutputDuration: TimeInterval {
        get throws {
            try sourceSegments.reduce(0) { $0 + $1.sourceRange.duration }
        }
    }

    public var outputDuration: TimeInterval {
        get throws {
            try unscaledOutputDuration / speed.value
        }
    }

    public func outputTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval? {
        guard sourceTime.isFinite, let segments = try? sourceSegments else {
            return nil
        }

        for segment in segments {
            if sourceTime >= segment.sourceRange.start, sourceTime < segment.sourceRange.end {
                return (segment.outputStart + sourceTime - segment.sourceRange.start) / speed.value
            }
            if sourceTime == segment.sourceRange.end {
                return (segment.outputStart + segment.sourceRange.duration) / speed.value
            }
        }
        return nil
    }

    public func sourceTime(forOutputTime outputTime: TimeInterval) -> TimeInterval? {
        guard outputTime.isFinite, outputTime >= 0, let segments = try? sourceSegments else {
            return nil
        }

        let unscaledTime = outputTime * speed.value
        for segment in segments {
            let outputEnd = segment.outputStart + segment.sourceRange.duration
            if unscaledTime >= segment.outputStart, unscaledTime < outputEnd {
                return segment.sourceRange.start + unscaledTime - segment.outputStart
            }
        }

        guard let last = segments.last,
            abs(unscaledTime - (last.outputStart + last.sourceRange.duration)) < 0.000_001
        else {
            return nil
        }
        return last.sourceRange.end
    }

    public func mapSourceRange(_ range: TimeRange) throws -> [TimeRange] {
        try sourceSegments.compactMap { segment in
            let start = max(range.start, segment.sourceRange.start)
            let end = min(range.end, segment.sourceRange.end)
            guard end > start else {
                return nil
            }

            return try TimeRange(
                start: (segment.outputStart + start - segment.sourceRange.start) / speed.value,
                end: (segment.outputStart + end - segment.sourceRange.start) / speed.value
            )
        }
    }
}

public enum TimelineEditingError: Error, Equatable, Sendable {
    case invalidCut
    case duplicateCutID
    case noRetainedMedia
    case insufficientRetainedDuration
    case noncontiguousTranscriptSelection
}
