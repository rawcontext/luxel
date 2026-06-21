import LuxelCore
import Testing

@Suite("Snap resolver")
struct SnapResolverTests {
    @Test("snaps candidate edges to screen edges within magnetism")
    func snapsCandidateEdgesToScreenEdgesWithinMagnetism() throws {
        let candidate = try CaptureRect(x: 7, y: 11, width: 320, height: 180)
        let screen = try CaptureRect(x: 0, y: 0, width: 1920, height: 1080)

        let result = try SnapResolver.resolve(
            candidate: candidate,
            screenFrames: [screen],
            magnetismRadius: 12
        )

        #expect(result.rect == (try CaptureRect(x: 0, y: 0, width: 320, height: 180)))
        #expect(
            result.guides == [
                CaptureSnapGuide(
                    axis: .vertical,
                    position: 0,
                    sourceAnchor: .leading,
                    targetAnchor: .leading,
                    targetKind: .screen
                ),
                CaptureSnapGuide(
                    axis: .horizontal,
                    position: 0,
                    sourceAnchor: .top,
                    targetAnchor: .top,
                    targetKind: .screen
                )
            ])
    }

    @Test("snaps to nearest window frame edge")
    func snapsToNearestWindowFrameEdge() throws {
        let candidate = try CaptureRect(x: 502, y: 411, width: 300, height: 200)
        let window = try CaptureRect(x: 200, y: 100, width: 300, height: 300)

        let result = try SnapResolver.resolve(
            candidate: candidate,
            windowFrames: [window],
            magnetismRadius: 12
        )

        #expect(result.rect == (try CaptureRect(x: 500, y: 400, width: 300, height: 200)))
        #expect(
            result.guides == [
                CaptureSnapGuide(
                    axis: .vertical,
                    position: 500,
                    sourceAnchor: .leading,
                    targetAnchor: .trailing,
                    targetKind: .window
                ),
                CaptureSnapGuide(
                    axis: .horizontal,
                    position: 400,
                    sourceAnchor: .top,
                    targetAnchor: .bottom,
                    targetKind: .window
                )
            ])
    }

    @Test("snaps centers and respects magnetism boundary")
    func snapsCentersAndRespectsMagnetismBoundary() throws {
        let screen = try CaptureRect(x: 0, y: 0, width: 1000, height: 800)
        let candidate = try CaptureRect(x: 353, y: 303, width: 300, height: 200)

        let snapped = try SnapResolver.resolve(
            candidate: candidate,
            screenFrames: [screen],
            magnetismRadius: 3
        )
        let outsideRadius = try SnapResolver.resolve(
            candidate: candidate,
            screenFrames: [screen],
            magnetismRadius: 2
        )

        #expect(snapped.rect == (try CaptureRect(x: 350, y: 300, width: 300, height: 200)))
        #expect(snapped.guides.map(\.sourceAnchor) == [.center, .middle])
        #expect(snapped.guides.map(\.targetAnchor) == [.center, .middle])
        #expect(outsideRadius.rect == candidate)
        #expect(outsideRadius.guides.isEmpty)
    }

    @Test("disabled snapping returns original rect without guides")
    func disabledSnappingReturnsOriginalRectWithoutGuides() throws {
        let candidate = try CaptureRect(x: 7, y: 7, width: 100, height: 100)
        let screen = try CaptureRect(x: 0, y: 0, width: 1000, height: 800)

        let result = try SnapResolver.resolve(
            candidate: candidate,
            screenFrames: [screen],
            magnetismRadius: 12,
            isDisabled: true
        )

        #expect(result.rect == candidate)
        #expect(result.guides.isEmpty)
    }

    @Test("negative magnetism radius is rejected")
    func negativeMagnetismRadiusIsRejected() throws {
        #expect(throws: CaptureModelError.invalidDimensions) {
            _ = try SnapResolver.resolve(
                candidate: CaptureRect(x: 10, y: 10, width: 100, height: 100),
                screenFrames: [CaptureRect(x: 0, y: 0, width: 1000, height: 800)],
                magnetismRadius: -1
            )
        }
    }
}
