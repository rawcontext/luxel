import Foundation
import LuxelCore
import Testing

@Suite("Edited timeline")
struct TimelineEditModelsTests {
    @Test("normalizes overlapping and touching cuts")
    func normalizesCuts() throws {
        let plan = try TimelineEditPlan(cuts: [
            cut(id: "second", start: 3, end: 5, spans: ["c"]),
            cut(id: "first", start: 1, end: 3, spans: ["a", "b"]),
            cut(id: "third", start: 4, end: 6, spans: ["d"])
        ])

        #expect(plan.cuts.count == 1)
        #expect(plan.cuts[0].sourceRange == (try TimeRange(start: 1, end: 6)))
        #expect(plan.cuts[0].transcriptSpanIDs == ["a", "b", "c", "d"])
    }

    @Test("clips cuts and builds kept source segments")
    func buildsKeptSegments() throws {
        let mapper = EditedTimelineMapper(
            trimRange: try TimeRange(start: 2, end: 12),
            editPlan: try TimelineEditPlan(cuts: [
                cut(id: "before", start: 0, end: 3),
                cut(id: "middle", start: 5, end: 7),
                cut(id: "after", start: 11, end: 15)
            ])
        )

        #expect(
            try mapper.sourceSegments == [
                SourceMediaSegment(
                    sourceRange: TimeRange(start: 3, end: 5),
                    outputStart: 0
                ),
                SourceMediaSegment(
                    sourceRange: TimeRange(start: 7, end: 11),
                    outputStart: 2
                )
            ]
        )
        #expect(try mapper.unscaledOutputDuration == 6)
    }

    @Test("maps source and output time across cuts and speed")
    func mapsTimes() throws {
        let mapper = EditedTimelineMapper(
            trimRange: try TimeRange(start: 10, end: 20),
            editPlan: try TimelineEditPlan(cuts: [
                cut(id: "middle", start: 12, end: 15)
            ]),
            speed: try PlaybackSpeed(2)
        )

        #expect(mapper.outputTime(forSourceTime: 11) == 0.5)
        #expect(mapper.outputTime(forSourceTime: 13) == nil)
        #expect(mapper.outputTime(forSourceTime: 15) == 1)
        #expect(mapper.sourceTime(forOutputTime: 0.5) == 11)
        #expect(mapper.sourceTime(forOutputTime: 1) == 15)
        #expect(mapper.sourceTime(forOutputTime: 3.5) == 20)
        #expect(try mapper.outputDuration == 3.5)
    }

    @Test("splits source ranges around removed media")
    func mapsSourceRanges() throws {
        let mapper = EditedTimelineMapper(
            trimRange: try TimeRange(start: 0, end: 10),
            editPlan: try TimelineEditPlan(cuts: [
                cut(id: "middle", start: 3, end: 5)
            ])
        )

        #expect(
            try mapper.mapSourceRange(TimeRange(start: 2, end: 7)) == [
                TimeRange(start: 2, end: 3),
                TimeRange(start: 3, end: 5)
            ]
        )
    }

    @Test("empty plan preserves continuous trim behavior")
    func emptyPlanParity() throws {
        let mapper = EditedTimelineMapper(
            trimRange: try TimeRange(start: 4, end: 9),
            speed: try PlaybackSpeed(2)
        )

        #expect(
            try mapper.sourceSegments == [
                SourceMediaSegment(
                    sourceRange: TimeRange(start: 4, end: 9),
                    outputStart: 0
                )
            ]
        )
        #expect(try mapper.outputDuration == 2.5)
        #expect(mapper.outputTime(forSourceTime: 6) == 1)
        #expect(mapper.sourceTime(forOutputTime: 1) == 6)
    }

    @Test("rejects an edit that removes the minimum retained duration")
    func protectsMinimumDuration() throws {
        let plan = TimelineEditPlan.empty

        #expect(throws: TimelineEditingError.insufficientRetainedDuration) {
            _ = try plan.inserting(
                cut(id: "all", start: 0, end: 9.95),
                within: TimeRange(start: 0, end: 10),
                minimumRetainedDuration: 0.1
            )
        }
    }

    private func cut(
        id: String,
        start: TimeInterval,
        end: TimeInterval,
        spans: [String] = []
    ) throws -> TimelineCut {
        try TimelineCut(
            id: id,
            sourceRange: TimeRange(start: start, end: end),
            kind: .transcriptSentence,
            transcriptSpanIDs: spans
        )
    }
}
