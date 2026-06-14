import Foundation
import LuxelCore
import Testing

@Suite("Zoom pan models")
struct ZoomPanModelTests {
    @Test("zoom blocks validate normalized rect zoom and transition duration")
    func zoomBlocksValidateNormalizedRectZoomAndTransitionDuration() throws {
        let rect = try NormalizedRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let block = try ZoomBlock(
            timeRange: TimeRange(start: 1, end: 3),
            targetRect: rect,
            zoom: 2,
            transitionOverride: 0.4
        )

        #expect(block.targetRect == rect)
        #expect(block.zoom == 2)
        #expect(block.transitionOverride == 0.4)

        #expect(throws: ZoomPanModelError.invalidNormalizedRect) {
            _ = try NormalizedRect(x: 0.8, y: 0, width: 0.3, height: 0.5)
        }
        #expect(throws: ZoomPanModelError.invalidZoom) {
            _ = try zoomBlock(start: 0, end: 1, zoom: 0.99)
        }
        #expect(throws: ZoomPanModelError.invalidZoom) {
            _ = try zoomBlock(start: 0, end: 1, zoom: 3.01)
        }
        #expect(throws: ZoomPanModelError.invalidTransitionDuration) {
            _ = try ZoomBlock(
                timeRange: TimeRange(start: 0, end: 1),
                targetRect: rect,
                zoom: 2,
                transitionOverride: 0
            )
        }
    }

    @Test("camera path validates sorted non overlapping blocks")
    func cameraPathValidatesSortedNonOverlappingBlocks() throws {
        let first = try zoomBlock(start: 0, end: 2)
        let second = try zoomBlock(start: 2, end: 4)
        let overlapping = try zoomBlock(start: 1.5, end: 3)

        let path = try CameraPath(
            blocks: [first, second],
            sourceSize: PixelSize(width: 100, height: 100)
        )

        #expect(path.blocks == [first, second])

        #expect(throws: ZoomPanModelError.unsortedBlocks) {
            _ = try CameraPath(
                blocks: [second, first],
                sourceSize: PixelSize(width: 100, height: 100)
            )
        }
        #expect(throws: ZoomPanModelError.overlappingBlocks) {
            _ = try CameraPath(
                blocks: [first, overlapping],
                sourceSize: PixelSize(width: 100, height: 100)
            )
        }
    }

    @Test("camera path returns identity outside blocks and clamps edge targets")
    func cameraPathReturnsIdentityOutsideBlocksAndClampsEdgeTargets() throws {
        let path = try CameraPath(
            blocks: [
                try zoomBlock(
                    start: 1,
                    end: 4,
                    rect: NormalizedRect(x: 0.75, y: 0.75, width: 0.1, height: 0.1),
                    zoom: 2,
                    transitionOverride: 0.5
                )
            ],
            sourceSize: PixelSize(width: 100, height: 100)
        )

        let before = try path.transform(at: 0.5)
        let settled = try path.transform(at: 2)
        let after = try path.transform(at: 4.5)

        #expect(before == .identity)
        #expect(settled.scale == 2)
        #expect(settled.sourceRect == (try NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)))
        #expect(after == .identity)
    }

    @Test("camera path interpolates with a bounded critically damped curve")
    func cameraPathInterpolatesWithBoundedCriticallyDampedCurve() throws {
        let path = try CameraPath(
            blocks: [
                try zoomBlock(
                    start: 1,
                    end: 4,
                    rect: NormalizedRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
                    zoom: 2,
                    transitionOverride: 1
                )
            ],
            sourceSize: PixelSize(width: 100, height: 100)
        )

        let start = try path.transform(at: 1)
        let mid = try path.transform(at: 1.5)
        let settled = try path.transform(at: 2)

        #expect(start == .identity)
        #expect(mid.scale > 1)
        #expect(mid.scale < 2)
        #expect(mid.sourceRect.x > 0)
        #expect(mid.sourceRect.x < 0.25)
        #expect(settled.scale == 2)
        #expect(settled.sourceRect == (try NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
    }

    @Test("adjacent zoom blocks pan directly without returning to full frame")
    func adjacentZoomBlocksPanDirectlyWithoutReturningToFullFrame() throws {
        let path = try CameraPath(
            blocks: [
                try zoomBlock(
                    start: 0,
                    end: 2,
                    rect: NormalizedRect(x: 0.2, y: 0.45, width: 0.1, height: 0.1),
                    zoom: 2,
                    transitionOverride: 1
                ),
                try zoomBlock(
                    start: 2,
                    end: 4,
                    rect: NormalizedRect(x: 0.7, y: 0.45, width: 0.1, height: 0.1),
                    zoom: 2,
                    transitionOverride: 1
                )
            ],
            sourceSize: PixelSize(width: 100, height: 100)
        )

        let beforeBoundary = try path.transform(at: 1.75)
        let atBoundary = try path.transform(at: 2)

        #expect(beforeBoundary.scale == 2)
        #expect(beforeBoundary.sourceRect.x > 0)
        #expect(beforeBoundary.sourceRect.x < 0.5)
        #expect(atBoundary.scale == 2)
        #expect(atBoundary.sourceRect.x == 0.5)
    }

    @Test("dead zone follow leaves centered cursor stable and shifts for edge drift")
    func deadZoneFollowLeavesCenteredCursorStableAndShiftsForEdgeDrift() throws {
        let path = try CameraPath(
            blocks: [
                try zoomBlock(
                    start: 0,
                    end: 4,
                    rect: NormalizedRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
                    zoom: 2,
                    transitionOverride: 0.5
                )
            ],
            sourceSize: PixelSize(width: 100, height: 100)
        )
        let centeredCursor = try CursorTimeline(
            samples: [
                try cursorSample(time: 2, x: 50, y: 50)
            ],
            cursorImages: [try cursorImage()]
        )
        let edgeCursor = try CursorTimeline(
            samples: [
                try cursorSample(time: 2, x: 80, y: 50)
            ],
            cursorImages: [try cursorImage()]
        )

        let centered = try path.transform(at: 2, cursorTimeline: centeredCursor)
        let followed = try path.transform(at: 2, cursorTimeline: edgeCursor)

        #expect(centered.sourceRect == (try NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)))
        #expect(abs(followed.sourceRect.x - 0.4) < 0.000_001)
        #expect(followed.sourceRect.y == 0.25)
        #expect(followed.sourceRect.width == 0.5)
        #expect(followed.sourceRect.height == 0.5)
    }

    @Test("camera path rejects invalid sample times")
    func cameraPathRejectsInvalidSampleTimes() throws {
        let path = try CameraPath(
            blocks: [],
            sourceSize: PixelSize(width: 100, height: 100)
        )

        #expect(throws: ZoomPanModelError.invalidTime) {
            _ = try path.transform(at: -.leastNonzeroMagnitude)
        }
        #expect(throws: ZoomPanModelError.invalidTime) {
            _ = try path.transform(at: .infinity)
        }
    }

    @Test("export time mapper trims scales and preserves block settings")
    func exportTimeMapperTrimsScalesAndPreservesBlockSettings() throws {
        let firstRect = try NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.2)
        let secondRect = try NormalizedRect(x: 0.6, y: 0.5, width: 0.2, height: 0.2)
        let blocks = [
            try zoomBlock(start: 0.5, end: 1.5),
            try zoomBlock(
                start: 1.5,
                end: 2.5,
                rect: firstRect,
                zoom: 1.4,
                transitionOverride: 0.6
            ),
            try zoomBlock(
                start: 3,
                end: 6.5,
                rect: secondRect,
                zoom: 2.2,
                transitionOverride: 1
            ),
            try zoomBlock(start: 6.5, end: 7)
        ]
        let mapper = try ZoomExportTimeMapper(
            trimRange: TimeRange(start: 2, end: 6),
            speed: PlaybackSpeed(2)
        )

        let mapped = try mapper.map(blocks)

        #expect(mapped == [
            try zoomBlock(
                start: 0,
                end: 0.25,
                rect: firstRect,
                zoom: 1.4,
                transitionOverride: 0.3
            ),
            try zoomBlock(
                start: 0.5,
                end: 2,
                rect: secondRect,
                zoom: 2.2,
                transitionOverride: 0.5
            )
        ])
    }

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

        let proposals = try ZoomProposalEngine.proposals(
            cursorTimeline: timeline,
            sourceSize: PixelSize(width: 100, height: 100)
        )
        let block = try #require(proposals.first)

        #expect(proposals.count == 1)
        #expect(abs(block.timeRange.start - 0.45) < 0.000_001)
        #expect(abs(block.timeRange.end - 1.95) < 0.000_001)
        #expect(abs(block.targetRect.x - 0.12) < 0.000_001)
        #expect(abs(block.targetRect.y - 0.22) < 0.000_001)
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

        let proposals = try ZoomProposalEngine.proposals(
            cursorTimeline: cursorTimeline,
            keystrokeTimeline: keystrokes,
            sourceSize: PixelSize(width: 100, height: 100)
        )
        let block = try #require(proposals.first)

        #expect(proposals.count == 1)
        #expect(abs(block.timeRange.start - 0.9) < 0.000_001)
        #expect(abs(block.timeRange.end - 2.4) < 0.000_001)
        #expect(abs(block.targetRect.x - 0.42) < 0.000_001)
        #expect(abs(block.targetRect.y - 0.32) < 0.000_001)
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

        let proposals = try ZoomProposalEngine.proposals(
            cursorTimeline: timeline,
            sourceSize: PixelSize(width: 100, height: 100)
        )
        let block = try #require(proposals.first)

        #expect(proposals.count == 1)
        #expect(block.timeRange == (try TimeRange(start: 0.25, end: 1.75)))
        #expect(abs(block.targetRect.x - 0.52) < 0.000_001)
        #expect(abs(block.targetRect.y - 0.32) < 0.000_001)
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

    private func zoomBlock(
        start: TimeInterval,
        end: TimeInterval,
        rect: NormalizedRect = try! NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
        zoom: Double = 1.6,
        transitionOverride: TimeInterval? = nil
    ) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: rect,
            zoom: zoom,
            transitionOverride: transitionOverride
        )
    }

    private func cursorImage() throws -> CursorImageAsset {
        try CursorImageAsset(
            id: "arrow",
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            hotspot: CursorPoint(x: 1, y: 1),
            scale: 2
        )
    }

    private func cursorSample(time: TimeInterval, x: Double, y: Double) throws -> CursorSample {
        try CursorSample(
            time: time,
            position: CursorPoint(x: x, y: y),
            cursorImageID: "arrow"
        )
    }

    private func keyDown(time: TimeInterval, keyCode: Int = 0) throws -> KeystrokeEvent {
        try KeystrokeEvent(
            time: time,
            kind: .keyDown,
            keyCode: keyCode,
            characters: "a"
        )
    }
}
