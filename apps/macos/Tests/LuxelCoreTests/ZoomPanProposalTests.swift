import Foundation
import LuxelCore
import Testing

extension ZoomPanModelTests {
    @Test("proposal engine clusters nearby clicks into zoom blocks")
    func proposalEngineClustersNearbyClicksIntoZoomBlocks() throws {
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 10, y: 10),
                try cursorSample(time: 1, x: 20, y: 30),
                try cursorSample(time: 1.4, x: 25, y: 35),
                try cursorSample(time: 6, x: 80, y: 80)
            ],
            clicks: [
                try CursorClickEvent(time: 1, button: .left, phase: .down),
                try CursorClickEvent(time: 1.4, button: .left, phase: .down)
            ],
            cursorImages: [try cursorImage()]
        )

        let (proposals, block) = try firstProposal(cursorTimeline: timeline)

        #expect(proposals.count == 1)
        #expect(abs(block.timeRange.start - 0.45) < 0.000_001)
        #expect(abs(block.timeRange.end - 1.95) < 0.000_001)
        #expect(abs(block.targetRect.originX - 0.12) < 0.000_001)
        #expect(abs(block.targetRect.originY - 0.22) < 0.000_001)
        #expect(abs(block.targetRect.width - 0.21) < 0.000_001)
        #expect(block.targetRect.width == block.targetRect.height)
        #expect(block.zoom == 3)
    }

    @Test("proposal engine ignores lone stray clicks")
    func proposalEngineIgnoresLoneStrayClicks() throws {
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 20, y: 20),
                try cursorSample(time: 1, x: 20, y: 20)
            ],
            clicks: [
                try CursorClickEvent(time: 1, button: .left, phase: .down)
            ],
            cursorImages: [try cursorImage()]
        )

        let proposals = try ZoomProposalEngine.proposals(
            cursorTimeline: timeline,
            sourceSize: PixelSize(width: 100, height: 100)
        )

        #expect(proposals.isEmpty)
    }

    @Test("proposal engine uses typing bursts at cursor positions")
    func proposalEngineUsesTypingBurstsAtCursorPositions() throws {
        let cursorTimeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 2, x: 50, y: 40),
                try cursorSample(time: 2.2, x: 52, y: 42),
                try cursorSample(time: 2.4, x: 54, y: 44)
            ],
            cursorImages: [try cursorImage()]
        )
        let keystrokes = try KeystrokeTimeline(events: [
            try keyDown(time: 2),
            try keyDown(time: 2.2),
            try keyDown(time: 2.4)
        ])

        let (proposals, block) = try firstProposal(
            cursorTimeline: cursorTimeline,
            keystrokeTimeline: keystrokes
        )

        #expect(proposals.count == 1)
        #expect(abs(block.timeRange.start - 0.9) < 0.000_001)
        #expect(abs(block.timeRange.end - 2.4) < 0.000_001)
        #expect(abs(block.targetRect.originX - 0.42) < 0.000_001)
        #expect(abs(block.targetRect.originY - 0.32) < 0.000_001)
        #expect(block.zoom == 3)
    }

    @Test("proposal engine falls back to dwell when no interaction events exist")
    func proposalEngineFallsBackToDwellWhenNoInteractionEventsExist() throws {
        let timeline = try CursorTimeline(
            samples: [
                try cursorSample(time: 0, x: 60, y: 40),
                try cursorSample(time: 1, x: 61, y: 40),
                try cursorSample(time: 2, x: 60, y: 41),
                try cursorSample(time: 4, x: 10, y: 10)
            ],
            cursorImages: [try cursorImage()]
        )

        let (proposals, block) = try firstProposal(cursorTimeline: timeline)

        #expect(proposals.count == 1)
        #expect(block.timeRange == (try TimeRange(start: 0.25, end: 1.75)))
        #expect(abs(block.targetRect.originX - 0.52) < 0.000_001)
        #expect(abs(block.targetRect.originY - 0.32) < 0.000_001)
    }

    @Test("proposal tuning validates bounds")
    func proposalTuningValidatesBounds() throws {
        let tuning = try ZoomProposalTuning(
            clusterTimeGap: 1,
            minimumClusterWeight: 1,
            minimumBlockDuration: 1,
            temporalPadding: 0,
            targetPadding: 0,
            minimumZoom: 1,
            maximumZoom: 2,
            dwellDurationThreshold: 1,
            dwellMovementTolerance: 0,
            maxProposals: 1
        )

        #expect(tuning.maximumZoom == 2)

        #expect(throws: ZoomPanModelError.invalidProposalTuning) {
            _ = try ZoomProposalTuning(clusterTimeGap: 0)
        }
        #expect(throws: ZoomPanModelError.invalidProposalTuning) {
            _ = try ZoomProposalTuning(minimumZoom: 0.9)
        }
        #expect(throws: ZoomPanModelError.invalidProposalTuning) {
            _ = try ZoomProposalTuning(maximumZoom: 3.1)
        }
        #expect(throws: ZoomPanModelError.invalidProposalTuning) {
            _ = try ZoomProposalTuning(maxProposals: 0)
        }
    }

    private func firstProposal(
        cursorTimeline: CursorTimeline,
        keystrokeTimeline: KeystrokeTimeline? = nil
    ) throws -> (proposals: [ZoomBlock], block: ZoomBlock) {
        let proposals = try ZoomProposalEngine.proposals(
            cursorTimeline: cursorTimeline,
            keystrokeTimeline: keystrokeTimeline,
            sourceSize: PixelSize(width: 100, height: 100)
        )
        return (proposals, try #require(proposals.first))
    }

    @Test("zoom block drafts track proposal acceptance edits and deletes")
    func zoomBlockDraftsTrackProposalAcceptanceEditsAndDeletes() throws {
        let id = try ZoomBlockDraftID("proposal-1")
        let original = try zoomBlock(start: 1, end: 3)
        let edited = try zoomBlock(
            start: 1,
            end: 3,
            rect: NormalizedRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
            zoom: 2
        )
        let draft = ZoomBlockDraft.proposal(id: id, block: original)
        let collection = try ZoomBlockDraftCollection([draft])

        #expect(collection.drafts.first?.state == .proposed)
        #expect(collection.drafts.first?.origin == .proposal)
        #expect(collection.activeBlocks == [original])

        let accepted = try collection.acceptingAllProposals()
        #expect(accepted.drafts.first?.state == .accepted)
        #expect(accepted.activeBlocks == [original])

        let replaced = try accepted.replacingBlock(id: id, with: edited)
        #expect(replaced.drafts.first?.state == .edited)
        #expect(replaced.drafts.first?.block == edited)
        #expect(replaced.activeBlocks == [edited])

        let deleted = try replaced.deleting(id: id)
        #expect(deleted.drafts.first?.state == .deleted)
        #expect(deleted.drafts.first?.block == edited)
        #expect(deleted.activeBlocks.isEmpty)
    }

    @Test("zoom block draft collection validates ids states and active timeline")
    func zoomBlockDraftCollectionValidatesIDsStatesAndActiveTimeline() throws {
        let id = try ZoomBlockDraftID("draft-1")
        let otherID = try ZoomBlockDraftID("draft-2")
        let first = try zoomBlock(start: 0, end: 2)
        let overlapping = try zoomBlock(start: 1.5, end: 3)

        #expect(throws: ZoomPanModelError.invalidDraftID) {
            _ = try ZoomBlockDraftID("   ")
        }
        #expect(throws: ZoomPanModelError.invalidDraftState) {
            _ = try ZoomBlockDraft(
                id: id,
                block: first,
                origin: .manual,
                state: .proposed
            )
        }
        #expect(throws: ZoomPanModelError.duplicateDraftID) {
            _ = try ZoomBlockDraftCollection([
                .manual(id: id, block: first),
                .proposal(id: id, block: try zoomBlock(start: 2, end: 4))
            ])
        }
        #expect(throws: ZoomPanModelError.overlappingBlocks) {
            _ = try ZoomBlockDraftCollection([
                .manual(id: id, block: first),
                .proposal(id: otherID, block: overlapping)
            ])
        }
        #expect(throws: ZoomPanModelError.unknownDraftID) {
            _ = try ZoomBlockDraftCollection([
                .manual(id: id, block: first)
            ]).deleting(id: otherID)
        }
    }

}
