import CoreGraphics
import Foundation
import LuxelCore
import Observation

struct CropperQuickRecordingConfiguration {
    let activePresetID: UUID?
    let presets: [ExportPreset]

    init(activePresetID: UUID?, presets: [ExportPreset]) {
        self.presets = presets
        self.activePresetID =
            if let activePresetID,
                presets.contains(where: { $0.id == activePresetID })
            {
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

struct CropperRestoreSelectionConfiguration {
    static let disabled = CropperRestoreSelectionConfiguration(isEnabled: false, memory: nil)

    let isEnabled: Bool
    let memory: LastCaptureMemory?

    func selection(for display: DisplayBounds, targets: [CaptureTargetOption] = []) -> CaptureRect? {
        guard isEnabled else {
            return nil
        }

        return memory?.restoredTopLeftSelection(in: display, availableTargets: targets)
    }
}

@MainActor
@Observable
final class CropperDisplayFocus {
    var activeDisplayID: DisplayID?

    func activate(_ displayID: DisplayID) {
        activeDisplayID = displayID
    }

    func clear(ifMatching displayID: DisplayID) {
        if activeDisplayID == displayID {
            activeDisplayID = nil
        }
    }

    func dimsDisplay(_ displayID: DisplayID, dimOtherDisplays: Bool) -> Bool {
        dimOtherDisplays && activeDisplayID != nil && activeDisplayID != displayID
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

struct CropperUndoState: Equatable, Sendable {
    let selection: CaptureRect?
    let aspectRatioPreset: CaptureAspectRatioPreset
    let customAspectRatio: CaptureAspectRatio?
    let customAspectRatioWidthText: String
    let customAspectRatioHeightText: String
}

@MainActor
@Observable
final class LuxelCropperModel {
    let display: DisplayBounds
    var selection: CaptureRect?
    var aspectRatioPreset: CaptureAspectRatioPreset = .free
    var customAspectRatio: CaptureAspectRatio?
    var customAspectRatioWidthText = "3"
    var customAspectRatioHeightText = "2"
    var snapGuides: [CaptureSnapGuide] = []
    var loupeSample: CaptureLoupeSample?
    var countdownDuration: TimeInterval?
    var stopAfterDuration: TimeInterval?
    var customStopAfterText: String
    var recordsAudio: Bool
    var capturesKeystrokes: Bool
    var errorMessage: String?
    @ObservationIgnored let onCountdownDurationChange: (TimeInterval?) -> Void
    @ObservationIgnored let onStopAfterDurationChange: (TimeInterval?) -> Void
    @ObservationIgnored let onRecordAudioChange: (Bool) -> Void
    @ObservationIgnored let onCaptureKeystrokesChange: (Bool) -> Void
    @ObservationIgnored let sizePresets: [CaptureSizePreset]
    @ObservationIgnored let windowSnapFrames: [CaptureRect]
    let canRecordAudio: Bool
    let canCaptureKeystrokes: Bool
    let loupeAlwaysOn: Bool
    let dimOtherDisplays: Bool
    let displayFocus: CropperDisplayFocus
    @ObservationIgnored var selectionUndoStack: UndoStack<CropperUndoState>
    @ObservationIgnored var resizeStartSelection: CaptureRect?
    @ObservationIgnored var moveStartSelection: CaptureRect?
    @ObservationIgnored var selectionDragID = 0
    @ObservationIgnored var resizeDragID = 0
    @ObservationIgnored var moveDragID = 0

    init(
        display: DisplayBounds,
        countdownDuration: TimeInterval? = nil,
        stopAfterDuration: TimeInterval? = nil,
        selectionPresetConfiguration: CropperSelectionPresetConfiguration =
            CropperSelectionPresetConfiguration(
                sizePresets: CaptureSizePreset.builtInDefaults
            ),
        initialSelection: CaptureRect? = nil,
        windowSnapFrames: [CaptureRect] = [],
        recordAudio: Bool = false,
        captureKeystrokes: Bool = false,
        canRecordAudio: Bool = false,
        canCaptureKeystrokes: Bool = false,
        loupeAlwaysOn: Bool = false,
        dimOtherDisplays: Bool = false,
        displayFocus: CropperDisplayFocus = CropperDisplayFocus(),
        onCountdownDurationChange: @escaping (TimeInterval?) -> Void = { _ in },
        onStopAfterDurationChange: @escaping (TimeInterval?) -> Void = { _ in },
        onRecordAudioChange: @escaping (Bool) -> Void = { _ in },
        onCaptureKeystrokesChange: @escaping (Bool) -> Void = { _ in }
    ) {
        let resolvedInitialSelection = Self.validInitialSelection(initialSelection, display: display)

        self.display = display
        self.selection = resolvedInitialSelection
        self.countdownDuration = countdownDuration
        self.stopAfterDuration = stopAfterDuration
        self.customStopAfterText = stopAfterDuration.map(RecordingDurationText.format) ?? "1:00"
        self.recordsAudio = recordAudio
        self.capturesKeystrokes = captureKeystrokes
        self.sizePresets = selectionPresetConfiguration.sizePresets
        self.windowSnapFrames = windowSnapFrames
        self.canRecordAudio = canRecordAudio
        self.canCaptureKeystrokes = canCaptureKeystrokes
        self.loupeAlwaysOn = loupeAlwaysOn
        self.dimOtherDisplays = dimOtherDisplays
        self.displayFocus = displayFocus
        self.onCountdownDurationChange = onCountdownDurationChange
        self.onStopAfterDurationChange = onStopAfterDurationChange
        self.onRecordAudioChange = onRecordAudioChange
        self.onCaptureKeystrokesChange = onCaptureKeystrokesChange
        if resolvedInitialSelection != nil {
            displayFocus.activate(display.id)
        }
        self.selectionUndoStack = UndoStack(
            initialState: CropperUndoState(
                selection: resolvedInitialSelection,
                aspectRatioPreset: .free,
                customAspectRatio: nil,
                customAspectRatioWidthText: "3",
                customAspectRatioHeightText: "2"
            ))
    }
}

extension LuxelCropperModel {
    var aspectRatioSummary: String {
        customAspectRatio.map { "\($0.width):\($0.height)" } ?? aspectRatioPreset.title
    }

    var canRecordSelection: Bool {
        selection != nil
    }

    var isDimmedByOtherDisplay: Bool {
        displayFocus.dimsDisplay(display.id, dimOtherDisplays: dimOtherDisplays)
    }

    var canUndoSelectionChange: Bool {
        selectionUndoStack.canUndo
    }

    var canRedoSelectionChange: Bool {
        selectionUndoStack.canRedo
    }

    var canToggleRecordAudio: Bool {
        canRecordAudio || recordsAudio
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

    func setRecordAudio(_ isEnabled: Bool) {
        guard recordsAudio != isEnabled else {
            return
        }

        guard !isEnabled || canRecordAudio else {
            return
        }

        recordsAudio = isEnabled
        onRecordAudioChange(isEnabled)
    }

    func setCaptureKeystrokes(_ isEnabled: Bool) {
        guard capturesKeystrokes != isEnabled else {
            return
        }
        guard !isEnabled || canCaptureKeystrokes else {
            return
        }
        capturesKeystrokes = isEnabled
        onCaptureKeystrokesChange(isEnabled)
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
        isSnappingDisabled: Bool = false,
        isLoupeRequested: Bool = false,
        loupeOverlaySize: CGSize = CGSize(width: 164, height: 122)
    ) {
        guard resizeStartSelection == nil, moveStartSelection == nil else {
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
                windowFrames: windowSnapFrames,
                screenFrames: [try displaySnapFrame],
                isDisabled: isSnappingDisabled
            )
            activateDisplay()
            selection = snapResult.rect
            snapGuides = snapResult.guides
            updateLoupe(
                cursor: capturePoint(from: current, viewSize: viewSize),
                viewSize: viewSize,
                overlaySize: loupeOverlaySize,
                isRequested: isLoupeRequested
            )
            pushUndoState(coalescingToken: selectionDragCoalescingToken)
            errorMessage = nil
        } catch {
            snapGuides = []
            clearLoupe()
            errorMessage = errorMessage(for: error)
        }
    }

    func finishUpdateSelection() {
        snapGuides = []
        clearLoupe()
        selectionDragID += 1
    }

    func moveSelection(
        translation: CGSize,
        viewSize: CGSize
    ) {
        guard resizeStartSelection == nil else {
            return
        }

        guard let selection else {
            return
        }

        if moveStartSelection == nil {
            moveStartSelection = selection
        }

        guard let moveStartSelection else {
            return
        }

        let delta = captureDelta(from: translation, viewSize: viewSize)
        guard delta.deltaX != 0 || delta.deltaY != 0 else {
            return
        }

        do {
            let draft = try CaptureSelectionDraft(display: display, topLeftSelection: moveStartSelection)
            self.selection = try draft.moved(by: delta).topLeftSelection
            activateDisplay()
            snapGuides = []
            clearLoupe()
            pushUndoState(coalescingToken: moveDragCoalescingToken)
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func finishMoveSelection() {
        moveStartSelection = nil
        clearLoupe()
        moveDragID += 1
    }
}
