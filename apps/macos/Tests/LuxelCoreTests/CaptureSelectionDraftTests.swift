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
        #expect(
            try draft.captureTarget
                == .area(
                    displayID: DisplayID(7),
                    rect: CaptureRect(x: 0, y: 0, width: 1440, height: 900)
                ))
    }

    @Test("draft uses top-left selection for ScreenCaptureKit recording target")
    func draftUsesTopLeftSelectionForRecordingTarget() throws {
        let display = try DisplayBounds(id: DisplayID(42), x: 0, y: 0, width: 1920, height: 1080)
        let selection = try CaptureRect(x: 100, y: 120, width: 640, height: 360)

        let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)

        #expect(try draft.pixelSize == PixelSize(width: 640, height: 360))
        #expect(
            try draft.captureTarget
                == .area(
                    displayID: DisplayID(42),
                    rect: selection
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

    @Test("side handle resize moves only that side")
    func sideHandleResizeMovesOnlyThatSide() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 180)
        )

        let resized = try draft.resized(
            dragging: .left,
            by: CaptureResizeDelta(x: -40, y: 90)
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 60, y: 100, width: 360, height: 180)))
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

    @Test("requested aspect ratio corner resize uses requested ratio")
    func requestedAspectRatioCornerResizeUsesRequestedRatio() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 200)
        )

        let resized = try draft.resized(
            dragging: .bottomRight,
            by: CaptureResizeDelta(x: 160, y: 10),
            aspectRatio: .widescreen16x9
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 100, width: 480, height: 270)))
    }

    @Test("requested aspect ratio side resize preserves ratio")
    func requestedAspectRatioSideResizePreservesRatio() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 200)
        )

        let resized = try draft.resized(
            dragging: .right,
            by: CaptureResizeDelta(x: 80, y: 90),
            aspectRatio: .widescreen16x9
        )

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 88, width: 400, height: 225)))
    }

}

extension CaptureSelectionDraftTests {
    @Test("exact selection replacement clamps to display and minimum size")
    func exactSelectionReplacementClampsToDisplayAndMinimumSize() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 80, width: 200, height: 120),
            minimumWidth: 40,
            minimumHeight: 30
        )

        let replaced = try draft.replacingSelection(
            x: 490,
            y: -20,
            width: 20,
            height: 800
        )

        #expect(replaced.topLeftSelection == (try CaptureRect(x: 460, y: 0, width: 40, height: 400)))
    }

    @Test("move nudge keeps selection inside display")
    func moveNudgeKeepsSelectionInsideDisplay() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 450, y: 360, width: 50, height: 40)
        )

        let moved = try draft.moved(by: CaptureResizeDelta(x: 10, y: 10))

        #expect(moved.topLeftSelection == (try CaptureRect(x: 450, y: 360, width: 50, height: 40)))
    }

    @Test("keyboard resize nudge preserves top-left anchor")
    func keyboardResizeNudgePreservesTopLeftAnchor() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 80, width: 200, height: 120),
            minimumWidth: 40,
            minimumHeight: 30
        )

        let resized = try draft.resized(by: CaptureResizeDelta(x: -500, y: 20))

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 80, width: 40, height: 140)))
    }

    @Test("aspect ratio presets resize around selection center")
    func aspectRatioPresetsResizeAroundSelectionCenter() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 200)
        )

        let resized = try draft.applyingAspectRatioPreset(.widescreen16x9)

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 110, width: 320, height: 180)))
    }

    @Test("vertical aspect ratio preset clamps to display height")
    func verticalAspectRatioPresetClampsToDisplayHeight() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 500, height: 400)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 80, width: 400, height: 200)
        )

        let resized = try draft.applyingAspectRatioPreset(.vertical9x16)

        #expect(resized.topLeftSelection == (try CaptureRect(x: 188, y: 0, width: 225, height: 400)))
    }

    @Test("custom aspect ratio resizes around selection center")
    func customAspectRatioResizesAroundSelectionCenter() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 200)
        )

        let resized = try draft.applyingAspectRatio(CaptureAspectRatio(width: 3, height: 2))

        #expect(resized.topLeftSelection == (try CaptureRect(x: 100, y: 94, width: 320, height: 213)))
    }

    @Test("size presets clamp oversized selections to display")
    func sizePresetsClampOversizedSelectionsToDisplay() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 180)
        )
        let preset = try CaptureSizePreset(
            name: "Huge",
            pixelSize: PixelSize(width: 1920, height: 1080)
        )

        let resized = try draft.applyingSizePreset(preset)

        #expect(resized.topLeftSelection == (try CaptureRect(x: 0, y: 0, width: 1000, height: 700)))
    }

    @Test("size presets keep requested size when it fits")
    func sizePresetsKeepRequestedSizeWhenItFits() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 250, y: 200, width: 200, height: 100)
        )
        let preset = try CaptureSizePreset(
            name: "Small",
            pixelSize: PixelSize(width: 400, height: 300)
        )

        let resized = try draft.applyingSizePreset(preset)

        #expect(resized.topLeftSelection == (try CaptureRect(x: 150, y: 100, width: 400, height: 300)))
    }

    @Test("undo stack coalesces cropper drag snapshots")
    func undoStackCoalescesCropperDragSnapshots() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 700)
        let initial = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 100, y: 100, width: 320, height: 180)
        )
        let firstDragUpdate = try initial.moved(by: CaptureResizeDelta(x: 10, y: 0))
        let finalDragUpdate = try initial.moved(by: CaptureResizeDelta(x: 80, y: 40))
        var stack = UndoStack(initialState: initial)

        stack.push(firstDragUpdate, coalescingToken: "drag-1")
        stack.push(finalDragUpdate, coalescingToken: "drag-1")

        #expect(stack.current == finalDragUpdate)
        #expect(stack.undoCount == 1)
        #expect(stack.undo() == initial)
        #expect(stack.redo() == finalDragUpdate)
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
