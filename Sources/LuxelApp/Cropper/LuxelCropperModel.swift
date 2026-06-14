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

enum LuxelCropperMode: String, CaseIterable, Identifiable {
    case video
    case photo

    var id: Self { self }
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
    var locksWidescreenRatio = false
    var countdownDuration: TimeInterval?
    var stopAfterDuration: TimeInterval?
    var customStopAfterText: String
    var errorMessage: String?
    @ObservationIgnored private let onCountdownDurationChange: (TimeInterval?) -> Void
    @ObservationIgnored private let onStopAfterDurationChange: (TimeInterval?) -> Void
    private var resizeStartSelection: CaptureRect?

    init(
        display: DisplayBounds,
        mode: LuxelCropperMode = .video,
        countdownDuration: TimeInterval? = nil,
        stopAfterDuration: TimeInterval? = nil,
        onCountdownDurationChange: @escaping (TimeInterval?) -> Void = { _ in },
        onStopAfterDurationChange: @escaping (TimeInterval?) -> Void = { _ in }
    ) {
        self.display = display
        self.mode = mode
        self.countdownDuration = countdownDuration
        self.stopAfterDuration = stopAfterDuration
        self.customStopAfterText = stopAfterDuration.map(RecordingDurationText.format) ?? "1:00"
        self.onCountdownDurationChange = onCountdownDurationChange
        self.onStopAfterDurationChange = onStopAfterDurationChange
    }

    var selectionSummary: String {
        guard let selection else {
            return "Select Area"
        }

        return "\(selection.width)x\(selection.height)"
    }

    var canRecordSelection: Bool {
        selection != nil
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

    func updateSelection(start: CGPoint, current: CGPoint, viewSize: CGSize) {
        guard resizeStartSelection == nil else {
            return
        }

        do {
            selection = try CaptureSelectionBuilder.selection(
                from: capturePoint(from: start, viewSize: viewSize),
                to: capturePoint(from: current, viewSize: viewSize),
                in: display,
                aspectRatio: locksWidescreenRatio ? try CaptureAspectRatio(width: 16, height: 9) : nil
            )
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
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
                lockingAspectRatio: locksWidescreenRatio
            ).topLeftSelection
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
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
    }

    func finishResizeSelection() {
        resizeStartSelection = nil
    }

    func selectFullDisplay() {
        do {
            selection = try CaptureSelectionBuilder.fullDisplaySelection(in: display)
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
        }
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
            errorMessage = nil
        } catch {
            errorMessage = errorMessage(for: error)
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
}
