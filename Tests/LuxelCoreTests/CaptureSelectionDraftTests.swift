import LuxelCore
import Testing

@Suite("Capture selection draft")
struct CaptureSelectionDraftTests {
    @Test("drag selection normalizes direction")
    func dragSelectionNormalizesDirection() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)

        let selection = try CaptureSelectionBuilder.selection(
            from: CapturePoint(x: 700, y: 500),
            to: CapturePoint(x: 300, y: 200),
            in: display
        )

        #expect(selection == (try CaptureRect(x: 300, y: 200, width: 400, height: 300)))
    }

    @Test("drag selection clamps to display bounds")
    func dragSelectionClampsToDisplayBounds() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 800, height: 600)

        let selection = try CaptureSelectionBuilder.selection(
            from: CapturePoint(x: 760, y: 560),
            to: CapturePoint(x: 900, y: 900),
            in: display
        )

        #expect(selection == (try CaptureRect(x: 760, y: 560, width: 40, height: 40)))
    }

    @Test("aspect ratio lock preserves requested ratio")
    func aspectRatioLockPreservesRatio() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1920, height: 1080)
        let ratio = try CaptureAspectRatio(width: 16, height: 9)

        let selection = try CaptureSelectionBuilder.selection(
            from: CapturePoint(x: 100, y: 100),
            to: CapturePoint(x: 700, y: 300),
            in: display,
            aspectRatio: ratio
        )

        #expect(selection == (try CaptureRect(x: 100, y: 100, width: 600, height: 338)))
    }

    @Test("full display selection covers the entire display")
    func fullDisplaySelectionCoversEntireDisplay() throws {
        let display = try DisplayBounds(id: DisplayID(7), x: -1440, y: 0, width: 1440, height: 900)

        let selection = try CaptureSelectionBuilder.fullDisplaySelection(in: display)
        let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)

        #expect(selection == (try CaptureRect(x: 0, y: 0, width: 1440, height: 900)))
        #expect(try draft.captureTarget == .area(
            displayID: DisplayID(7),
            rect: CaptureRect(x: 0, y: 0, width: 1440, height: 900)
        ))
    }

    @Test("draft converts top-left selection to ScreenCaptureKit recording target")
    func draftConvertsTopLeftSelectionToRecordingTarget() throws {
        let display = try DisplayBounds(id: DisplayID(42), x: 0, y: 0, width: 1920, height: 1080)
        let selection = try CaptureRect(x: 100, y: 120, width: 640, height: 360)

        let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)

        #expect(try draft.pixelSize == PixelSize(width: 640, height: 360))
        #expect(try draft.captureTarget == .area(
            displayID: DisplayID(42),
            rect: CaptureRect(x: 100, y: 600, width: 640, height: 360)
        ))
    }

    @Test("resize bottom-right expands selection")
    func resizeBottomRightExpandsSelection() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 180)
        )

        let resized = try draft.resized(
            dragging: .bottomRight,
            by: CaptureResizeDelta(x: 80, y: 40)
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 100, width: 400, height: 220)))
    }

    @Test("resize clamps moving edges to display bounds")
    func resizeClampsMovingEdgesToDisplayBounds() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 80, width: 260, height: 180)
        )

        let resized = try draft.resized(
            dragging: .bottomRight,
            by: CaptureResizeDelta(x: 400, y: 400)
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 80, width: 400, height: 320)))
    }

    @Test("resize top-left keeps opposite corner and enforces minimum size")
    func resizeTopLeftKeepsOppositeCornerAndEnforcesMinimumSize() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 200, height: 150),
            minimumWidth: 32,
            minimumHeight: 24
        )

        let resized = try draft.resized(
            dragging: .topLeft,
            by: CaptureResizeDelta(x: 500, y: 500)
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 268, y: 226, width: 32, height: 24)))
    }

    @Test("aspect locked corner resize preserves original ratio")
    func aspectLockedCornerResizePreservesOriginalRatio() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 180)
        )

        let resized = try draft.resized(
            dragging: .bottomRight,
            by: CaptureResizeDelta(x: 160, y: 10),
            lockingAspectRatio: true
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 100, width: 480, height: 270)))
    }

    @Test("invalid resize minimums throw")
    func invalidResizeMinimumsThrow() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let selection = try CaptureRect(x: 100, y: 100, width: 200, height: 150)

        #expect(throws: CaptureModelError.invalidDimensions) {
            _ = try CaptureSelectionDraft(
                display: display,
                topLeftSelection: selection,
                minimumWidth: 0,
                minimumHeight: 24
            )
        }
    }
}
