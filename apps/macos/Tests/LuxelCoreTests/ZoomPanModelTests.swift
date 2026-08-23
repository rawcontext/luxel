import Foundation
import LuxelCore
import Testing

@Suite("Zoom pan models")
struct ZoomPanModelTests {
}

extension ZoomPanModelTests {
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
        #expect(mid.sourceRect.originX > 0)
        #expect(mid.sourceRect.originX < 0.25)
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
        #expect(beforeBoundary.sourceRect.originX > 0)
        #expect(beforeBoundary.sourceRect.originX < 0.5)
        #expect(atBoundary.scale == 2)
        #expect(atBoundary.sourceRect.originX == 0.5)
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
        #expect(abs(followed.sourceRect.originX - 0.4) < 0.000_001)
        #expect(followed.sourceRect.originY == 0.25)
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

        #expect(
            mapped == [
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

    func zoomBlock(
        start: TimeInterval,
        end: TimeInterval,
        rect: NormalizedRect? = nil,
        zoom: Double = 1.6,
        transitionOverride: TimeInterval? = nil
    ) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: rect ?? NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
            zoom: zoom,
            transitionOverride: transitionOverride
        )
    }

    func cursorImage() throws -> CursorImageAsset {
        try CursorImageAsset(
            id: "arrow",
            pngData: Data([0x89, 0x50, 0x4E, 0x47]),
            hotspot: CursorPoint(x: 1, y: 1),
            scale: 2
        )
    }

    func cursorSample(time: TimeInterval, x xCoordinate: Double, y yCoordinate: Double) throws
        -> CursorSample
    {
        try CursorSample(
            time: time,
            position: CursorPoint(x: xCoordinate, y: yCoordinate),
            cursorImageID: "arrow"
        )
    }

    func keyDown(time: TimeInterval, keyCode: Int = 0) throws -> KeystrokeEvent {
        try KeystrokeEvent(
            time: time,
            kind: .keyDown,
            keyCode: keyCode,
            characters: "a"
        )
    }
}
