import AppKit
import LuxelCore
import SwiftUI

extension LuxelCropperView {
    func commitPrimarySelection() {
        let quickPresetID: UUID? =
            if NSEvent.modifierFlags.contains(.option) {
                quickRecordingConfiguration.activePresetID
            } else {
                nil
            }

        commitSelection(quickPresetID: quickPresetID)
    }

    func commitSelection(quickPresetID: UUID? = nil) {
        do {
            guard let draft = try model.draft() else {
                return
            }

            if let quickPresetID {
                onQuickSelect(draft, quickPresetID)
            } else {
                onSelect(draft)
            }
        } catch {
            NSSound.beep()
        }
    }

    @ViewBuilder
    func countdownButton(title: String, duration: TimeInterval?) -> some View {
        Button {
            model.setCountdownDuration(duration)
        } label: {
            if model.countdownDuration == duration {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .help(countdownHelp(title: title, duration: duration))
    }

    @ViewBuilder
    func stopAfterButton(title: String, duration: TimeInterval?) -> some View {
        Button {
            model.setStopAfterDuration(duration)
        } label: {
            if model.stopAfterDuration == duration {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .help(stopAfterHelp(title: title, duration: duration))
    }

    func applyCustomStopAfterDuration() {
        guard model.applyCustomStopAfterDuration() else {
            NSSound.beep()
            return
        }
    }

    func applyCustomAspectRatio() {
        guard model.applyCustomAspectRatio() else {
            NSSound.beep()
            return
        }
    }

    var customStopAfterText: Binding<String> {
        Binding {
            model.customStopAfterText
        } set: { text in
            model.setCustomStopAfterText(text)
        }
    }

    var customAspectRatioWidthText: Binding<String> {
        Binding {
            model.customAspectRatioWidthText
        } set: { text in
            model.setCustomAspectRatioWidthText(text)
        }
    }

    var customAspectRatioHeightText: Binding<String> {
        Binding {
            model.customAspectRatioHeightText
        } set: { text in
            model.setCustomAspectRatioHeightText(text)
        }
    }

    var recordAudio: Binding<Bool> {
        Binding {
            model.recordsAudio
        } set: { isEnabled in
            model.setRecordAudio(isEnabled)
        }
    }

    @ViewBuilder
    func cameraDeviceButton(title: String, deviceID: String?) -> some View {
        Button {
            let cameraConfiguration = effectiveCameraConfiguration
            currentCameraConfiguration = CropperCameraConfiguration(
                selectedDeviceID: deviceID,
                devices: cameraConfiguration.devices,
                previewStyle: cameraConfiguration.previewStyle
            )
            onCameraSelectionChange(deviceID)
        } label: {
            if effectiveCameraConfiguration.selectedDeviceID == deviceID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .help(deviceID == nil ? "Turn off the camera overlay." : "Use \(title) as the camera overlay.")
    }

    var effectiveCameraConfiguration: CropperCameraConfiguration {
        currentCameraConfiguration ?? cameraConfiguration
    }

    var cameraToolbarText: String {
        effectiveCameraConfiguration.selectedDevice?.name ?? "Camera Off"
    }

    var cameraMenuSystemImage: String {
        effectiveCameraConfiguration.selectedDeviceID == nil ? "video.slash" : "video.fill"
    }

    var cameraMenuHelp: String {
        if let selectedDevice = effectiveCameraConfiguration.selectedDevice {
            return "Camera overlay: \(selectedDevice.name)."
        }

        return "Choose a camera overlay for the recording."
    }

    var selectionSummaryHelp: String {
        guard let selection = model.selection else {
            return "Drag to select the area to record."
        }

        return "Selected area: \(selection.width) by \(selection.height) pixels."
    }

    var recordAudioHelp: String {
        if !model.canToggleRecordAudio {
            return "Microphone permission is required to record mic audio."
        }

        return model.recordsAudio
            ? "Record microphone audio with this capture."
            : "Do not record microphone audio with this capture."
    }

    var primaryActionHelp: String {
        guard model.canRecordSelection else {
            return "Drag to select an area first."
        }

        return model.primaryActionHelp
    }

    var compactCountdownToolbarText: String {
        "Delay \(compactDurationSummary(model.countdownDuration))"
    }

    var aspectRatioToolbarText: String {
        "Aspect \(model.aspectRatioSummary)"
    }

    var compactStopAfterToolbarText: String {
        "Stop \(compactDurationSummary(model.stopAfterDuration))"
    }

    var microphoneToolbarText: String {
        model.recordsAudio ? "Mic On" : "Mic Off"
    }

    private func compactDurationSummary(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "Off"
        }

        if duration < 60 {
            return "\(Int(duration))s"
        }

        return "\(Int(duration / 60))m"
    }

    private func countdownHelp(title: String, duration: TimeInterval?) -> String {
        duration == nil ? "Start recording immediately." : "Wait \(title) before recording starts."
    }

    private func stopAfterHelp(title: String, duration: TimeInterval?) -> String {
        duration == nil ? "Keep recording until stopped manually." : "Stop recording after \(title)."
    }

    func updateCameraPreviewShape(_ shape: CameraOverlayShape) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: shape,
            size: style.size,
            isMirrored: style.isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    func updateCameraPreviewSize(_ size: CameraPreviewSize) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: style.shape,
            size: size,
            isMirrored: style.isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    func updateCameraPreviewMirror(_ isMirrored: Bool) {
        let cameraConfiguration = effectiveCameraConfiguration
        let style = cameraConfiguration.previewStyle
        let updatedStyle = CameraPreviewStyle(
            shape: style.shape,
            size: style.size,
            isMirrored: isMirrored
        )
        updateCameraPreviewStyle(updatedStyle, from: cameraConfiguration)
    }

    private func updateCameraPreviewStyle(
        _ style: CameraPreviewStyle,
        from cameraConfiguration: CropperCameraConfiguration
    ) {
        currentCameraConfiguration = CropperCameraConfiguration(
            selectedDeviceID: cameraConfiguration.selectedDeviceID,
            devices: cameraConfiguration.devices,
            previewStyle: style
        )
        onCameraPreviewStyleChange(style)
    }

    func quickPresetSystemImage(for preset: ExportPreset) -> String {
        preset.id == quickRecordingConfiguration.activePresetID ? "bolt.circle.fill" : "bolt.circle"
    }

    func openFocusSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")
        else {
            return
        }

        openURL(url)
    }
}
