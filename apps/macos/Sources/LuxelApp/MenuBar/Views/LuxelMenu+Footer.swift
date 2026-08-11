import AppKit
import LuxelCore
import SwiftUI

extension LuxelMenu {
    var footerControls: some View {
        HStack(spacing: 0) {
            systemAudioFooterControl

            Spacer(minLength: 6)

            microphoneFooterControl

            Spacer(minLength: 6)

            cameraFooterControl

            Spacer(minLength: 6)

            overflowFooterMenu
        }
        .frame(maxWidth: .infinity)
    }

    var overflowFooterMenu: some View {
        Menu {
            overflowMenuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: Self.deviceCircleButtonSize, height: Self.deviceCircleButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
        .frame(height: Self.deviceControlHeight)
        .help("More Luxel actions.")
    }

    var microphoneFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .microphone)
        return footerSourceControl(
            presentation: presentation,
            accessibilityLabel: "Microphone",
            action: { handleMicrophoneFooterAction(presentation) },
            picker: { microphoneFooterPicker }
        )
    }

    var cameraFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .camera)

        return footerSourceControl(
            presentation: presentation,
            accessibilityLabel: "Camera",
            action: { handleCameraFooterAction(presentation) },
            picker: { cameraFooterPicker }
        )
    }

    var footerControlDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 18)
    }

    var systemAudioFooterControl: some View {
        let presentation = model.sourcePermissionPresentation(for: .systemAudio)

        return footerSourceControl(
            presentation: presentation,
            accessibilityLabel: "System Audio",
            action: { handleSystemAudioFooterAction(presentation) },
            picker: { systemAudioFooterPicker(presentation) }
        )
    }

    func footerSourceControl<Picker: View>(
        presentation: CaptureSourcePermissionPresentation,
        accessibilityLabel: String,
        action: @escaping () -> Void,
        @ViewBuilder picker: () -> Picker
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: action) {
                footerSourceIcon(presentation)
                    .frame(width: Self.deviceIconCellWidth, height: Self.deviceControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(
                LuxelIslandCellButtonStyle(
                    corners: .leading,
                    cornerRadius: Self.deviceControlCornerRadius
                )
            )
            .help(presentation.message)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(presentation.statusTitle)

            footerControlDivider
            picker()
        }
        .luxelIslandControlGroupBackground(cornerRadius: Self.deviceControlCornerRadius)
    }

    func systemAudioFooterPicker(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> some View {
        Menu {
            Picker("Audio Source", selection: systemAudioFooterSelection(presentation)) {
                Text("Off").tag(false)
                Text("System Audio").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            footerPickerChevronLabel(width: 30, height: Self.deviceControlHeight)
        }
        .buttonStyle(
            LuxelIslandCellButtonStyle(
                corners: .trailing,
                cornerRadius: Self.deviceControlCornerRadius
            )
        )
        .frame(height: Self.deviceControlHeight)
        .help("Choose audio source")
        .accessibilityLabel("Choose Audio Source")
        .accessibilityValue(model.settings.recordSystemAudio ? "System Audio" : "Off")
    }

    func footerPickerChevronLabel(width: CGFloat, height: CGFloat) -> some View {
        Image(systemName: "chevron.down")
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white.opacity(0.55))
            .frame(width: width, height: height)
            .contentShape(Rectangle())
    }

    func systemAudioFooterSelection(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> Binding<Bool> {
        Binding {
            model.settings.recordSystemAudio
        } set: { isEnabled in
            guard isEnabled else {
                model.settings.recordSystemAudio = false
                model.saveSettings()
                return
            }

            switch presentation.phase {
            case .ready, .offByUser:
                model.settings.recordSystemAudio = true
                model.saveSettings()
            case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
                 .pausedByMacOS, .blocked:
                presentPermissionPrompt(.systemAudio)
            }
        }
    }

    func footerSourceIcon(
        _ presentation: CaptureSourcePermissionPresentation
    ) -> some View {
        Image(systemName: presentation.systemImage)
            .labelStyle(.iconOnly)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(presentation.phase == .ready ? 0.92 : 0.42))
    }

    @ViewBuilder
    var overflowMenuItems: some View {
        Button {
            openLuxelSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
        }

        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Label("Quit Luxel", systemImage: "power")
        }
    }

    func showAreaCapturePicker() {
        model.refreshCameraDevices()
        let camera = model.cropperCameraConfiguration()
        let quickRecording = model.cropperQuickRecordingConfiguration()
        let selectionPresets = model.cropperSelectionPresetConfiguration()
        let restoredSelection = model.cropperRestoreSelectionConfiguration()
        cropperPanelController.show(
            countdownDuration: model.settings.defaultCountdown,
            stopAfterDuration: model.settings.lastStopAfter,
            canRecordAudio: model.microphoneStatus == .authorized,
            canCaptureKeystrokes: model.inputMonitoringStatus == .authorized,
            cameraConfiguration: camera,
            quickRecordingConfiguration: quickRecording,
            selectionPresetConfiguration: selectionPresets,
            restoreSelectionConfiguration: restoredSelection,
            recordAudio: model.captureCapabilities.microphoneTrackAvailable,
            captureKeystrokes: model.settings.keystrokeOverlayEnabled,
            loupeAlwaysOn: model.settings.loupeAlwaysOn,
            dimOtherDisplays: model.settings.dimOtherDisplays,
            showsNotificationReminder: false,
            onCountdownDurationChange: updateCropperCountdown,
            onStopAfterDurationChange: updateCropperStopAfter,
            onRecordAudioChange: updateCropperAudio,
            onCaptureKeystrokesChange: updateCropperKeystrokes,
            onCameraSelectionChange: updateCropperCamera,
            onCameraPreviewStyleChange: updateCropperCameraStyle,
            onNotificationReminderDismiss: model.dismissNotificationReminder,
            onQuickSelect: { draft, presetID in
                Task {
                    await model.startQuickRecording(from: draft, presetID: presetID)
                }
            },
            onSelect: { draft in
                Task {
                    await model.startRecording(from: draft)
                }
            }
        )
    }

    func updateCropperCountdown(_ duration: TimeInterval?) {
        model.settings.defaultCountdown = duration
        model.saveSettings()
    }

    func updateCropperStopAfter(_ duration: TimeInterval?) {
        model.settings.lastStopAfter = duration
        model.saveSettings()
    }

    func updateCropperAudio(_ isEnabled: Bool) {
        guard !isEnabled || model.microphoneStatus == .authorized else {
            presentPermissionPrompt(.microphone)
            return
        }
        model.settings.recordAudio = isEnabled
        model.saveSettings()
    }

    func updateCropperKeystrokes(_ isEnabled: Bool) {
        model.settings.keystrokeOverlayEnabled = isEnabled
        model.saveSettings()
    }

    func updateCropperCamera(_ deviceID: String?) {
        Task { await model.setCameraDeviceFromCropper(deviceID) }
    }

    func updateCropperCameraStyle(_ style: CameraPreviewStyle) {
        Task { await model.setCameraPreviewStyleFromCropper(style) }
    }

    func startAfterDismissingMenu(_ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            await action()
        }
    }

    func openRecording(_ url: URL) {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            openEditorWindow()
            model.configureEditor(editorModel)
            await editorModel.open(
                fileURL: url,
                outputDirectory: model.settings.recordingsDirectory,
                outputDirectoryBookmark: model.settings.recordingsDirectoryBookmark,
                transcriptSourceContext: model.transcriptSourceContext(for: url)
            )
        }
    }

    func openLuxelSettings() {
        Task { @MainActor in
            dismissMenu()
            await Task.yield()
            openSettingsWindow()
        }
    }

    func openRecentRecording(_ recording: PastRecording) {
        openRecording(recording.primaryMediaURL)
    }

    func revealRecentRecording(_ recording: PastRecording) {
        dismissMenu()
        model.revealRecording(recording)
    }

    func recentRecordingOpenTitle(for recording: PastRecording) -> String {
        "Open in editor"
    }

    func recentRecordingTitle(for recording: PastRecording) -> String {
        recording.name.components(separatedBy: " at ").first ?? recording.name
    }

    func refreshMenuState() async {
        model.refreshRecentRecordings()
        model.refreshAudioInputDevices()
        model.refreshCameraDevices()
        await model.refreshPermissions()
        await model.refreshCaptureTargets()
    }

    var recoveryPromptPresented: Binding<Bool> {
        Binding {
            model.recoveryPrompt != nil
        } set: { isPresented in
            if !isPresented {
                model.recoveryPrompt = nil
            }
        }
    }

    var automationPromptPresented: Binding<Bool> {
        Binding {
            model.automationPrompt != nil
        } set: { isPresented in
            if !isPresented {
                model.denyAutomationPrompt()
            }
        }
    }

    func handleSystemAudioFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.settings.recordSystemAudio = false
            model.saveSettings()
        case .offByUser:
            model.settings.recordSystemAudio = true
            model.saveSettings()
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.systemAudio)
        }
    }

    func handleMicrophoneFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.settings.recordAudio = false
            model.saveSettings()
        case .offByUser:
            model.settings.recordAudio = true
            model.saveSettings()
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.microphone)
        }
    }

    func handleCameraFooterAction(_ presentation: CaptureSourcePermissionPresentation) {
        switch presentation.phase {
        case .ready:
            model.disableCameraSource()
        case .offByUser:
            Task {
                await model.enableDefaultCameraSource()
            }
        case .checking, .needsGrant, .requestInProgress, .openSettings, .grantedNeedsRelaunch,
             .pausedByMacOS, .blocked:
            presentPermissionPrompt(.camera)
        }
    }
}
