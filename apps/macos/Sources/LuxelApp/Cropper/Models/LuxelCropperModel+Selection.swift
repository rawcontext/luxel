import CoreGraphics
import Foundation
import LuxelCore

@MainActor
extension LuxelCropperModel {
    func resizeSelection(
        handle: CaptureResizeHandle,
        translation: CGSize,
        viewSize: CGSize,
        lockingAspectRatio: Bool = false,
        isLoupeRequested: Bool = false,
        loupeOverlaySize: CGSize = CGSize(width: 164, height: 122)
    ) {
        guard moveStartSelection == nil else {
            return
        }

        guard let selection else {
            return
        }

        if resizeStartSelection == nil {
            resizeStartSelection = selection
        }

        guard let resizeStartSelection else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(
                display: display,
                topLeftSelection: resizeStartSelection
            )
            self.selection = try draft.resized(
                dragging: handle,
                by: captureDelta(from: translation, viewSize: viewSize),
                lockingAspectRatio: lockingAspectRatio,
                aspectRatio: activeAspectRatio
            ).topLeftSelection
            activateDisplay()
            updateLoupe(
                cursor: handle.cursorPoint(in: self.selection),
                viewSize: viewSize,
                overlaySize: loupeOverlaySize,
                isRequested: isLoupeRequested
            )
            pushUndoState(coalescingToken: resizeDragCoalescingToken)
            errorMessage = nil
        } catch {
            clearLoupe()
            errorMessage = errorMessage(for: error)
        }
    }

    func setAspectRatioPreset(_ preset: CaptureAspectRatioPreset) {
        guard aspectRatioPreset != preset || customAspectRatio != nil else {
            return
        }

        aspectRatioPreset = preset
        customAspectRatio = nil

        applyActiveAspectRatioToSelection()
    }

    func applyCustomAspectRatio() -> Bool {
        do {
            let width = try Self.parseCustomAspectRatioComponent(customAspectRatioWidthText)
            let height = try Self.parseCustomAspectRatioComponent(customAspectRatioHeightText)
            aspectRatioPreset = .free
            customAspectRatio = try CaptureAspectRatio(width: width, height: height)
            applyActiveAspectRatioToSelection()
            return true
        } catch {
            errorMessage = LuxelLocalization.string("Use whole-number ratio values greater than 0")
            return false
        }
    }

    func applyActiveAspectRatioToSelection() {
        guard let selection else {
            pushUndoState()
            errorMessage = nil
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.applyingAspectRatio(activeAspectRatio).topLeftSelection
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func applySizePreset(_ preset: CaptureSizePreset) {
        do {
            let startingSelection: CaptureRect
            if let selection {
                startingSelection = selection
            } else {
                startingSelection = try CaptureSelectionBuilder.fullDisplaySelection(in: display)
            }
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: startingSelection)
            selection = try draft.applyingSizePreset(preset).topLeftSelection
            activateDisplay()
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func setSelectionSize(width: Int, height: Int) -> Bool {
        guard let selection, width > 0, height > 0 else {
            return false
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.replacingSelection(width: width, height: height)
                .topLeftSelection
            activateDisplay()
            pushUndoState()
            errorMessage = nil
            return true
        } catch {
            errorMessage = errorMessage(for: error)
            return false
        }
    }

    func nudgeSelection(x deltaX: Int, y deltaY: Int) {
        guard let selection else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.moved(by: CaptureResizeDelta(x: deltaX, y: deltaY))
                .topLeftSelection
            activateDisplay()
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func resizeSelectionBy(width: Int, height: Int) {
        guard let selection else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.resized(by: CaptureResizeDelta(x: width, y: height))
                .topLeftSelection
            activateDisplay()
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func finishResizeSelection() {
        resizeStartSelection = nil
        clearLoupe()
        resizeDragID += 1
    }

    func selectFullDisplay() {
        do {
            selection = try CaptureSelectionBuilder.fullDisplaySelection(in: display)
            activateDisplay()
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func undoSelectionChange() {
        guard let state = selectionUndoStack.undo() else {
            return
        }

        applyUndoState(state)
    }

    func redoSelectionChange() {
        guard let state = selectionUndoStack.redo() else {
            return
        }

        applyUndoState(state)
    }

    func viewRect(for selection: CaptureRect, in viewSize: CGSize) -> CGRect {
        let scaleX = viewSize.width / Double(display.width)
        let scaleY = viewSize.height / Double(display.height)

        return CGRect(
            x: Double(selection.originX) * scaleX,
            y: Double(selection.originY) * scaleY,
            width: Double(selection.width) * scaleX,
            height: Double(selection.height) * scaleY
        )
    }

    func draft() throws -> CaptureSelectionDraft? {
        guard let selection else {
            return nil
        }

        return try CaptureSelectionDraft(display: display, topLeftSelection: selection)
    }

    var selectionDragCoalescingToken: String {
        "selection-drag-\(selectionDragID)"
    }

    var resizeDragCoalescingToken: String {
        "resize-drag-\(resizeDragID)"
    }

    var moveDragCoalescingToken: String {
        "move-drag-\(moveDragID)"
    }

    var currentUndoState: CropperUndoState {
        CropperUndoState(
            selection: selection,
            aspectRatioPreset: aspectRatioPreset,
            customAspectRatio: customAspectRatio,
            customAspectRatioWidthText: customAspectRatioWidthText,
            customAspectRatioHeightText: customAspectRatioHeightText
        )
    }

    func pushUndoState(coalescingToken: String? = nil) {
        selectionUndoStack.push(currentUndoState, coalescingToken: coalescingToken)
    }

    func applyUndoState(_ state: CropperUndoState) {
        selection = state.selection
        aspectRatioPreset = state.aspectRatioPreset
        customAspectRatio = state.customAspectRatio
        customAspectRatioWidthText = state.customAspectRatioWidthText
        customAspectRatioHeightText = state.customAspectRatioHeightText
        updateDisplayFocusForCurrentSelection()
        errorMessage = nil
    }

    func activateDisplay() {
        displayFocus.activate(display.id)
    }

    func updateDisplayFocusForCurrentSelection() {
        if selection == nil {
            displayFocus.clear(ifMatching: display.id)
        } else {
            activateDisplay()
        }
    }

    func updateLoupe(
        cursor: CapturePoint,
        viewSize: CGSize,
        overlaySize: CGSize,
        isRequested: Bool
    ) {
        guard shouldShowLoupe(isRequested: isRequested),
            let overlayPixelSize = loupeOverlayPixelSize(viewSize: viewSize, overlaySize: overlaySize)
        else {
            clearLoupe()
            return
        }

        guard
            let sample = try? CaptureLoupeSampleResolver.sample(
                cursor: cursor,
                display: display,
                selection: selection,
                overlaySize: overlayPixelSize
            )
        else {
            clearLoupe()
            return
        }

        loupeSample = sample
    }

    func clearLoupe() {
        loupeSample = nil
    }

    func shouldShowLoupe(isRequested: Bool) -> Bool {
        loupeAlwaysOn || isRequested
    }

    func loupeOverlayPixelSize(viewSize: CGSize, overlaySize: CGSize) -> PixelSize? {
        guard viewSize.width > 0,
            viewSize.height > 0,
            overlaySize.width > 0,
            overlaySize.height > 0
        else {
            return nil
        }

        return try? PixelSize(
            width: max(1, Int((overlaySize.width / viewSize.width * Double(display.width)).rounded(.up))),
            height: max(
                1, Int((overlaySize.height / viewSize.height * Double(display.height)).rounded(.up)))
        )
    }

    var activeAspectRatio: CaptureAspectRatio? {
        customAspectRatio ?? aspectRatioPreset.aspectRatio
    }

    var displaySnapFrame: CaptureRect {
        get throws {
            try CaptureRect(x: 0, y: 0, width: display.width, height: display.height)
        }
    }

    func capturePoint(from point: CGPoint, viewSize: CGSize) -> CapturePoint {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return CapturePoint(x: 0, y: 0)
        }

        return CapturePoint(
            x: Int((point.x / viewSize.width * Double(display.width)).rounded()),
            y: Int((point.y / viewSize.height * Double(display.height)).rounded())
        )
    }

    func captureDelta(from translation: CGSize, viewSize: CGSize) -> CaptureResizeDelta {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return CaptureResizeDelta(x: 0, y: 0)
        }

        return CaptureResizeDelta(
            x: Int((translation.width / viewSize.width * Double(display.width)).rounded()),
            y: Int((translation.height / viewSize.height * Double(display.height)).rounded())
        )
    }

    func errorMessage(for error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }

    static func durationSummary(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return LuxelLocalization.format("recording.countdown.seconds", defaultValue: "%d s", Int(duration))
        }

        let minutes = Int(duration / 60)
        return LuxelLocalization.format("%d min", minutes)
    }

    static func validInitialSelection(_ selection: CaptureRect?, display: DisplayBounds)
        -> CaptureRect? {
        guard let selection,
            (try? CaptureSelectionDraft(display: display, topLeftSelection: selection)) != nil
        else {
            return nil
        }

        return selection
    }

    static func parseCustomAspectRatioComponent(_ text: String) throws -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
            value > 0
        else {
            throw CaptureModelError.invalidDimensions
        }

        return value
    }
}
