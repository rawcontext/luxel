import Foundation
import LuxelCore
import Observation

struct CropperAudioLevelConfiguration {
    let deviceID: String?
}

struct CropperQuickRecordingConfiguration {
    let activePresetID: UUID?
    let presets: [ExportPreset]

    init(activePresetID: UUID?, presets: [ExportPreset]) {
        self.presets = presets
        self.activePresetID = if let activePresetID,
                                 presets.contains(where: { $0.id == activePresetID }) {
            activePresetID
        } else {
            nil
        }
    }
}

struct CropperSelectionPresetConfiguration {
    let sizePresets: [CaptureSizePreset]

    init(sizePresets: [CaptureSizePreset]) {
        self.sizePresets = sizePresets.isEmpty ? CaptureSizePreset.builtInDefaults : sizePresets
    }
}

struct CropperCameraConfiguration {
    let selectedDeviceID: String?
    let devices: [CameraDeviceOption]
    let previewStyle: CameraPreviewStyle

    var selectedDevice: CameraDeviceOption? {
        guard let selectedDeviceID else {
            return nil
        }

        return devices.first { $0.id == selectedDeviceID }
    }
}

enum LuxelCropperMode: String, CaseIterable, Identifiable, Sendable {
    case video
    case photo

    var id: Self { self }
}

private struct CropperUndoState: Equatable, Sendable {
    let selection: CaptureRect?
    let aspectRatioPreset: CaptureAspectRatioPreset
    let customAspectRatio: CaptureAspectRatio?
    let customAspectRatioWidthText: String
    let customAspectRatioHeightText: String
    let mode: LuxelCropperMode
}

@MainActor
@Observable
final class LuxelAudioLevelModel {
    var sample: AudioLevelSample = .silent

    @ObservationIgnored private let deviceID: String?
    @ObservationIgnored private let monitor: any AudioLevelMonitor

    init(deviceID: String?, monitor: any AudioLevelMonitor) {
        self.deviceID = deviceID
        self.monitor = monitor
    }

    func watch() async {
        sample = .silent

        for await sample in monitor.start(deviceID: deviceID) {
            self.sample = sample
        }
    }

    func stop() {
        monitor.stop()
    }
}

@MainActor
@Observable
final class LuxelCropperModel {
    let display: DisplayBounds
    var selection: CaptureRect?
    var mode: LuxelCropperMode
    var aspectRatioPreset: CaptureAspectRatioPreset = .free
    var customAspectRatio: CaptureAspectRatio?
    var customAspectRatioWidthText = "3"
    var customAspectRatioHeightText = "2"
    var snapGuides: [CaptureSnapGuide] = []
    var countdownDuration: TimeInterval?
    var stopAfterDuration: TimeInterval?
    var customStopAfterText: String
    var errorMessage: String?
    @ObservationIgnored private let onCountdownDurationChange: (TimeInterval?) -> Void
    @ObservationIgnored private let onStopAfterDurationChange: (TimeInterval?) -> Void
    @ObservationIgnored let sizePresets: [CaptureSizePreset]
    @ObservationIgnored private var selectionUndoStack: UndoStack<CropperUndoState>
    @ObservationIgnored private var resizeStartSelection: CaptureRect?
    @ObservationIgnored private var selectionDragID = 0
    @ObservationIgnored private var resizeDragID = 0

    init(
        display: DisplayBounds,
        mode: LuxelCropperMode = .video,
        countdownDuration: TimeInterval? = nil,
        stopAfterDuration: TimeInterval? = nil,
        selectionPresetConfiguration: CropperSelectionPresetConfiguration = CropperSelectionPresetConfiguration(
            sizePresets: CaptureSizePreset.builtInDefaults
        ),
        onCountdownDurationChange: @escaping (TimeInterval?) -> Void = { _ in },
        onStopAfterDurationChange: @escaping (TimeInterval?) -> Void = { _ in }
    ) {
        self.display = display
        self.mode = mode
        self.countdownDuration = countdownDuration
        self.stopAfterDuration = stopAfterDuration
        self.customStopAfterText = stopAfterDuration.map(RecordingDurationText.format) ?? "1:00"
        self.sizePresets = selectionPresetConfiguration.sizePresets
        self.onCountdownDurationChange = onCountdownDurationChange
        self.onStopAfterDurationChange = onStopAfterDurationChange
        self.selectionUndoStack = UndoStack(initialState: CropperUndoState(
            selection: nil,
            aspectRatioPreset: .free,
            customAspectRatio: nil,
            customAspectRatioWidthText: "3",
            customAspectRatioHeightText: "2",
            mode: mode
        ))
    }

    var selectionSummary: String {
        guard let selection else {
            return "Select Area"
        }

        return "\(selection.width)x\(selection.height)"
    }

    var aspectRatioSummary: String {
        customAspectRatio.map { "\($0.width):\($0.height)" } ?? aspectRatioPreset.title
    }

    var canRecordSelection: Bool {
        selection != nil
    }

    var canUndoSelectionChange: Bool {
        selectionUndoStack.canUndo
    }

    var canRedoSelectionChange: Bool {
        selectionUndoStack.canRedo
    }

    var stopAfterSummary: String {
        guard let stopAfterDuration else {
            return "Off"
        }

        return Self.durationSummary(stopAfterDuration)
    }

    var countdownSummary: String {
        guard let countdownDuration else {
            return "Off"
        }

        return Self.durationSummary(countdownDuration)
    }

    func setCountdownDuration(_ duration: TimeInterval?) {
        guard countdownDuration != duration else {
            return
        }

        countdownDuration = duration
        onCountdownDurationChange(duration)
    }

    func setStopAfterDuration(_ duration: TimeInterval?) {
        guard stopAfterDuration != duration else {
            return
        }

        stopAfterDuration = duration
        if let duration {
            customStopAfterText = RecordingDurationText.format(duration)
        }
        onStopAfterDurationChange(duration)
    }

    func setCustomStopAfterText(_ text: String) {
        customStopAfterText = text
    }

    func setCustomAspectRatioWidthText(_ text: String) {
        customAspectRatioWidthText = text
    }

    func setCustomAspectRatioHeightText(_ text: String) {
        customAspectRatioHeightText = text
    }

    func setMode(_ mode: LuxelCropperMode) {
        guard self.mode != mode else {
            return
        }

        self.mode = mode
        pushUndoState()
    }

    func applyCustomStopAfterDuration() -> Bool {
        do {
            let duration = try RecordingDurationText.parse(customStopAfterText)
            setStopAfterDuration(duration)
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Use h:mm:ss from 0:01 to 12:00:00"
            return false
        }
    }

    func updateSelection(
        start: CGPoint,
        current: CGPoint,
        viewSize: CGSize,
        isSnappingDisabled: Bool = false
    ) {
        guard resizeStartSelection == nil else {
            return
        }

        do {
            let candidate = try CaptureSelectionBuilder.selection(
                from: capturePoint(from: start, viewSize: viewSize),
                to: capturePoint(from: current, viewSize: viewSize),
                in: display,
                aspectRatio: activeAspectRatio
            )
            let snapResult = try SnapResolver.resolve(
                candidate: candidate,
                screenFrames: [try displaySnapFrame],
                isDisabled: isSnappingDisabled
            )
            selection = snapResult.rect
            snapGuides = snapResult.guides
            pushUndoState(coalescingToken: selectionDragCoalescingToken)
            errorMessage = nil
        } catch {
            snapGuides = []
            errorMessage = errorMessage(for: error)
        }
    }

    func finishUpdateSelection() {
        snapGuides = []
        selectionDragID += 1
    }

    func resizeSelection(handle: CaptureResizeHandle, translation: CGSize, viewSize: CGSize) {
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
                lockingAspectRatio: activeAspectRatio != nil
            ).topLeftSelection
            pushUndoState(coalescingToken: resizeDragCoalescingToken)
            errorMessage = nil
        } catch {
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
            errorMessage = "Use whole-number ratio values greater than 0"
            return false
        }
    }

    private func applyActiveAspectRatioToSelection() {
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
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func setSelectionX(_ x: Int) {
        replaceSelection(x: x)
    }

    func setSelectionY(_ y: Int) {
        replaceSelection(y: y)
    }

    func setSelectionWidth(_ width: Int) {
        replaceSelection(width: width)
    }

    func setSelectionHeight(_ height: Int) {
        replaceSelection(height: height)
    }

    func nudgeSelection(x: Int, y: Int) {
        guard let selection else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.moved(by: CaptureResizeDelta(x: x, y: y)).topLeftSelection
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
            self.selection = try draft.resized(by: CaptureResizeDelta(x: width, y: height)).topLeftSelection
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func finishResizeSelection() {
        resizeStartSelection = nil
        resizeDragID += 1
    }

    func selectFullDisplay() {
        do {
            selection = try CaptureSelectionBuilder.fullDisplaySelection(in: display)
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
            x: Double(selection.x) * scaleX,
            y: Double(selection.y) * scaleY,
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

    private func replaceSelection(
        x: Int? = nil,
        y: Int? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) {
        guard let selection else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: selection)
            self.selection = try draft.replacingSelection(
                x: x,
                y: y,
                width: width,
                height: height
            ).topLeftSelection
            pushUndoState()
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    private var selectionDragCoalescingToken: String {
        "selection-drag-\(selectionDragID)"
    }

    private var resizeDragCoalescingToken: String {
        "resize-drag-\(resizeDragID)"
    }

    private var currentUndoState: CropperUndoState {
        CropperUndoState(
            selection: selection,
            aspectRatioPreset: aspectRatioPreset,
            customAspectRatio: customAspectRatio,
            customAspectRatioWidthText: customAspectRatioWidthText,
            customAspectRatioHeightText: customAspectRatioHeightText,
            mode: mode
        )
    }

    private func pushUndoState(coalescingToken: String? = nil) {
        selectionUndoStack.push(currentUndoState, coalescingToken: coalescingToken)
    }

    private func applyUndoState(_ state: CropperUndoState) {
        selection = state.selection
        aspectRatioPreset = state.aspectRatioPreset
        customAspectRatio = state.customAspectRatio
        customAspectRatioWidthText = state.customAspectRatioWidthText
        customAspectRatioHeightText = state.customAspectRatioHeightText
        mode = state.mode
        errorMessage = nil
    }

    private var activeAspectRatio: CaptureAspectRatio? {
        customAspectRatio ?? aspectRatioPreset.aspectRatio
    }

    private var displaySnapFrame: CaptureRect {
        get throws {
            try CaptureRect(x: 0, y: 0, width: display.width, height: display.height)
        }
    }

    private func capturePoint(from point: CGPoint, viewSize: CGSize) -> CapturePoint {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return CapturePoint(x: 0, y: 0)
        }

        return CapturePoint(
            x: Int((point.x / viewSize.width * Double(display.width)).rounded()),
            y: Int((point.y / viewSize.height * Double(display.height)).rounded())
        )
    }

    private func captureDelta(from translation: CGSize, viewSize: CGSize) -> CaptureResizeDelta {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return CaptureResizeDelta(x: 0, y: 0)
        }

        return CaptureResizeDelta(
            x: Int((translation.width / viewSize.width * Double(display.width)).rounded()),
            y: Int((translation.height / viewSize.height * Double(display.height)).rounded())
        )
    }

    private func errorMessage(for error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }

    private static func durationSummary(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration)) s"
        }

        let minutes = Int(duration / 60)
        return "\(minutes) min"
    }

    private static func parseCustomAspectRatioComponent(_ text: String) throws -> Int {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        return value
    }
}
