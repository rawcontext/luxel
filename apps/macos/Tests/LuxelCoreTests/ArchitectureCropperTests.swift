import Foundation
import Testing

extension ArchitectureTests {
    @Test("cropper supports local selection undo and redo")
    func cropperSupportsLocalSelectionUndoAndRedo() throws {
        let packageRoot = try packageRootURL()
        let modelSource = try cropperModelSource()
        let viewSource = try sourceContents(
            under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))

        #expect(modelSource.contains("UndoStack<CropperUndoState>"))
        #expect(modelSource.contains("selection: CaptureRect?"))
        #expect(modelSource.contains("aspectRatioPreset: CaptureAspectRatioPreset"))
        #expect(modelSource.contains("customAspectRatio: CaptureAspectRatio?"))
        #expect(modelSource.contains("pushUndoState(coalescingToken: selectionDragCoalescingToken)"))
        #expect(modelSource.contains("pushUndoState(coalescingToken: resizeDragCoalescingToken)"))
        #expect(modelSource.contains("func applyCustomAspectRatio() -> Bool"))
        #expect(modelSource.contains("func undoSelectionChange()"))
        #expect(modelSource.contains("func redoSelectionChange()"))
        #expect(viewSource.contains("model.finishUpdateSelection()"))
        #expect(viewSource.contains("TextField(\"Custom W\", text: customAspectRatioWidthText)"))
        #expect(viewSource.contains("TextField(\"Custom H\", text: customAspectRatioHeightText)"))
        #expect(viewSource.contains("applyCustomAspectRatio()"))
        #expect(viewSource.contains("model.undoSelectionChange()"))
        #expect(viewSource.contains("model.redoSelectionChange()"))
        #expect(viewSource.contains(".keyboardShortcut(\"z\", modifiers: .command)"))
        #expect(viewSource.contains(".keyboardShortcut(\"z\", modifiers: [.command, .shift])"))
    }

    @Test("cropper edits custom stop duration in a focusable popover")
    func cropperEditsCustomStopDurationInPopover() throws {
        let packageRoot = try packageRootURL()
        let viewSource = try sourceContents(
            under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views"))

        #expect(viewSource.contains("@State var isEditingStopAfterDuration = false"))
        #expect(viewSource.contains("@FocusState var isCustomStopAfterFocused: Bool"))
        #expect(viewSource.contains("isEditingStopAfterDuration = true"))
        #expect(
            viewSource.contains(
                ".popover(isPresented: $isEditingStopAfterDuration, arrowEdge: .bottom)"))
        #expect(viewSource.contains("var stopAfterDurationEditor: some View"))
        #expect(viewSource.contains("TextField(\"h:mm:ss\", text: customStopAfterText)"))
        #expect(viewSource.contains("isEditingStopAfterDuration = false"))
    }

    @Test("cropper renders snap guides while drawing selections")
    func cropperRendersSnapGuidesWhileDrawingSelections() throws {
        let sources = try cropperSources()
        let modelSource = sources.model
        let controllerSource = sources.controller
        let viewSource = sources.views

        #expect(modelSource.contains("var snapGuides: [CaptureSnapGuide]"))
        #expect(modelSource.contains("let windowSnapFrames: [CaptureRect]"))
        #expect(modelSource.contains("SnapResolver.resolve("))
        #expect(modelSource.contains("windowFrames: windowSnapFrames"))
        #expect(modelSource.contains("screenFrames: [try displaySnapFrame]"))
        #expect(modelSource.contains("snapGuides = snapResult.guides"))
        #expect(modelSource.contains("snapGuides = []"))
        #expect(controllerSource.contains("let targets = try await targetService.availableTargets()"))
        #expect(controllerSource.contains("CaptureWindowSnapFrameResolver.windowFrames("))
        #expect(viewSource.contains("snapGuidesOverlay(viewSize: geometry.size)"))
        #expect(viewSource.contains("ForEach(Array(model.snapGuides.enumerated())"))
        #expect(viewSource.contains("let flags = NSEvent.modifierFlags"))
        #expect(viewSource.contains("flags.contains(.command)"))
    }

    @Test("cropper keeps active aspect ratio while drawing and resizing selections")
    func cropperKeepsActiveAspectRatioWhileDrawingAndResizingSelections() throws {
        let modelSource = try cropperModelSource()
        let activeAspectRatioUses =
            modelSource.components(separatedBy: "aspectRatio: activeAspectRatio").count - 1

        #expect(activeAspectRatioUses >= 2)
        #expect(modelSource.contains("lockingAspectRatio: lockingAspectRatio"))
    }

    @Test("cropper restores last area selection when enabled")
    func cropperRestoresLastAreaSelectionWhenEnabled() throws {
        let modelSource = try cropperModelSource()
        let controllerSource = try sourceText(for: [
            "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"
        ])
        let menuSource = try sourceText(for: [
            "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift",
            "Sources/LuxelApp/MenuBar/Views/LuxelMenu+Footer.swift"
        ])
        let shortcutsSource = try sourceText(for: [
            "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"
        ])
        let presentationSource = try sourceText(for: [
            "Sources/LuxelApp/MenuBar/Models/LuxelMenuModel+Presentation.swift"
        ])
        let normalizedControllerSource = controllerSource.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        #expect(modelSource.contains("struct CropperRestoreSelectionConfiguration"))
        #expect(
            modelSource.contains(
                "memory?.restoredTopLeftSelection(in: display, availableTargets: targets)"))
        #expect(modelSource.contains("initialSelection: CaptureRect? = nil"))
        #expect(modelSource.contains("selection: resolvedInitialSelection"))
        #expect(
            controllerSource.contains(
                "restoreSelectionConfiguration: CropperRestoreSelectionConfiguration = .disabled"))
        #expect(
            normalizedControllerSource.contains(
                "initialSelection: presentation.restoreSelectionConfiguration.selection("
                    + " for: display, targets: targets)"
            )
        )
        #expect(presentationSource.contains("isEnabled: settings.restoreLastSelection"))
        #expect(presentationSource.contains("memory: settings.lastCaptureMemory"))
        #expect(
            menuSource.contains(
                "let restoredSelection = model.cropperRestoreSelectionConfiguration()"))
        #expect(menuSource.contains("restoreSelectionConfiguration: restoredSelection"))
        #expect(
            shortcutsSource.contains(
                "restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration()"))
    }

    @Test("cropper dims inactive displays when configured")
    func cropperDimsInactiveDisplaysWhenConfigured() throws {
        let sources = try cropperSources()
        let modelSource = sources.model
        let controllerSource = sources.controller
        let viewSource = sources.views
        let menuSource = sources.menu
        let shortcutsSource = sources.shortcuts

        #expect(modelSource.contains("final class CropperDisplayFocus"))
        #expect(
            modelSource.contains(
                "func dimsDisplay(_ displayID: DisplayID, dimOtherDisplays: Bool) -> Bool"))
        #expect(modelSource.contains("var isDimmedByOtherDisplay: Bool"))
        #expect(modelSource.contains("displayFocus.activate(display.id)"))
        #expect(modelSource.contains("displayFocus.clear(ifMatching: display.id)"))
        #expect(controllerSource.contains("let displayFocus = CropperDisplayFocus()"))
        #expect(controllerSource.contains("dimOtherDisplays: dimOtherDisplays"))
        #expect(viewSource.contains("Color.black.opacity(model.isDimmedByOtherDisplay ? 0.20 : 0.38)"))
        #expect(
            viewSource.contains("if let selection = model.selection, !model.isDimmedByOtherDisplay"))
        #expect(menuSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
        #expect(shortcutsSource.contains("dimOtherDisplays: model.settings.dimOtherDisplays"))
    }

    @Test("cropper shows loupe during precision selection")
    func cropperShowsLoupeDuringPrecisionSelection() throws {
        let sources = try cropperSources()
        let modelSource = sources.model
        let controllerSource = sources.controller
        let viewSource = sources.views
        let menuSource = sources.menu
        let shortcutsSource = sources.shortcuts

        #expect(modelSource.contains("var loupeSample: CaptureLoupeSample?"))
        #expect(modelSource.contains("let loupeAlwaysOn: Bool"))
        #expect(modelSource.contains("CaptureLoupeSampleResolver.sample("))
        #expect(modelSource.contains("loupeSample = nil"))
        #expect(controllerSource.contains("loupeAlwaysOn: Bool = false"))
        #expect(controllerSource.contains("loupeAlwaysOn: loupeAlwaysOn"))
        #expect(viewSource.contains("struct CropperLoupeView"))
        #expect(viewSource.contains("struct CropperLoupeGrid"))
        #expect(viewSource.contains("let isLoupeRequested = flags.contains(.option)"))
        #expect(viewSource.contains("isSnappingDisabled: flags.contains(.command) || isLoupeActive"))
        #expect(menuSource.contains("loupeAlwaysOn: model.settings.loupeAlwaysOn"))
        #expect(shortcutsSource.contains("loupeAlwaysOn: model.settings.loupeAlwaysOn"))
    }

    private func cropperModelSource() throws -> String {
        try sourceText(for: [
            "Sources/LuxelApp/Cropper/Models/LuxelCropperModel.swift",
            "Sources/LuxelApp/Cropper/Models/LuxelCropperModel+Selection.swift"
        ])
    }

    private func cropperSources() throws -> CropperSources {
        let packageRoot = try packageRootURL()
        return try CropperSources(
            model: cropperModelSource(),
            controller: sourceText(for: [
                "Sources/LuxelApp/Cropper/Panels/LuxelCropperPanelController.swift"
            ]),
            views: sourceContents(
                under: packageRoot.appending(path: "Sources/LuxelApp/Cropper/Views")
            ),
            menu: sourceText(for: [
                "Sources/LuxelApp/MenuBar/Views/LuxelMenu.swift",
                "Sources/LuxelApp/MenuBar/Views/LuxelMenu+Footer.swift"
            ]),
            shortcuts: sourceText(for: [
                "Sources/LuxelApp/Shortcuts/LuxelShortcutInstaller.swift"
            ])
        )
    }
}

private struct CropperSources {
    let model: String
    let controller: String
    let views: String
    let menu: String
    let shortcuts: String
}
