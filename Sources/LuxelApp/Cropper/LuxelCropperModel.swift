import Foundation
import LuxelCore
import Observation

struct CropperAudioLevelConfiguration {
    let deviceID: String?
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
    var stopAfterDuration: TimeInterval?
    var customStopAfterText: String
    var errorMessage: String?
    @ObservationIgnored private let onStopAfterDurationChange: (TimeInterval?) -> Void
    private var resizeStartSelection: CaptureRect?

    init(
        display: DisplayBounds,
        mode: LuxelCropperMode = .video,
        stopAfterDuration: TimeInterval? = nil,
        onStopAfterDurationChange: @escaping (TimeInterval?) -> Void = { _ in }
    ) {
        self.display = display
        self.mode = mode
        self.stopAfterDuration = stopAfterDuration
        self.customStopAfterText = stopAfterDuration.map(RecordingDurationText.format) ?? "1:00"
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
