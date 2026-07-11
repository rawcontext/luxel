import Foundation
import LuxelCore
import Testing

@Suite("Timeline overlay mapping")
struct TimelineOverlayMapperTests {
    @Test("zoom mapper splits blocks around timeline cuts")
    func zoomMapperSplitsBlocks() throws {
        let block = try ZoomBlock(
            timeRange: TimeRange(start: 1, end: 7),
            targetRect: NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
            zoom: 1.6
        )
        let mapper = try ZoomExportTimeMapper(
            trimRange: TimeRange(start: 0, end: 8),
            editPlan: editPlan()
        )

        #expect(try mapper.map([block]).map(\.timeRange) == [
            TimeRange(start: 1, end: 3),
            TimeRange(start: 3, end: 5)
        ])
    }

    @Test("caption mapper splits cues around timeline cuts")
    func captionMapperSplitsCues() throws {
        let track = try CaptionTrack(
            cues: [
                CaptionCue(
                    timeRange: TimeRange(start: 1, end: 7),
                    text: "Spanning cue"
                )
            ],
            language: Locale.LanguageCode("en")
        )
        let mapper = try CaptionExportTimeMapper(
            trimRange: TimeRange(start: 0, end: 8),
            editPlan: editPlan()
        )

        #expect(try mapper.map(track).cues.map(\.timeRange) == [
            TimeRange(start: 1, end: 3),
            TimeRange(start: 3, end: 5)
        ])
    }

    private func editPlan() throws -> TimelineEditPlan {
        try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "cut",
                sourceRange: TimeRange(start: 3, end: 5),
                kind: .transcriptSentence
            )
        ])
    }
}
