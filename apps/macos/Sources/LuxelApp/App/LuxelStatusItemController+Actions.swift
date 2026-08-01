import AppKit
import LuxelCore
import LuxelPresentation
import OSLog
import SwiftUI

@MainActor
extension LuxelStatusItemController {
    func rememberActivationSourceApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
            return
        }

        activationSourceApplication = frontmostApplication
    }

    func openEditorFromPopover() {
        windowPresenter.openEditor(activationSource: activationSourceApplication)
    }

    func openSettingsFromPopover() {
        windowPresenter.openSettings(activationSource: activationSourceApplication)
    }

    func presentPendingPermissionPromptIfNeeded() {
        guard !isPresentingPermissionPrompt,
              let prompt = model.permissionPrompt
        else {
            return
        }

        presentPermissionPrompt(prompt)
    }

    func presentPendingReplayBufferConsentIfNeeded() {
        guard !isPresentingReplayBufferConsent,
              let prompt = model.replayBufferConsentPrompt
        else {
            return
        }

        presentReplayBufferConsent(prompt)
    }

    func presentReplayBufferConsent(_ prompt: ReplayBufferConsentPrompt) {
        guard !isPresentingReplayBufferConsent else {
            model.replayBufferConsentPrompt = prompt
            return
        }

        isPresentingReplayBufferConsent = true
        model.replayBufferConsentPrompt = nil
        closePopover()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }

            let accepted = runReplayBufferConsentAlert()
            isPresentingReplayBufferConsent = false

            if accepted {
                model.replayBufferConsentPrompt = prompt
                await model.approveReplayBufferConsent()
            } else {
                model.denyReplayBufferConsent()
            }

            presentPendingReplayBufferConsentIfNeeded()
        }
    }

    func presentPermissionPrompt(for source: CapturePermissionSource) {
        presentPermissionPrompt(model.makePermissionPrompt(forSource: source))
    }

    func presentPermissionPrompt(_ prompt: PermissionPrompt) {
        guard !isPresentingPermissionPrompt else {
            model.permissionPrompt = prompt
            return
        }

        isPresentingPermissionPrompt = true
        model.permissionPrompt = nil
        closePopover()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }

            let shouldPerformAction = runPermissionAlert(prompt)
            isPresentingPermissionPrompt = false

            if shouldPerformAction {
                await model.performPermissionAction(prompt)
            } else {
                model.permissionPrompt = nil
            }

            presentPendingPermissionPromptIfNeeded()
        }
    }

    func runPermissionAlert(_ prompt: PermissionPrompt) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = prompt.guidance.title
        alert.informativeText = prompt.guidance.message

        let primaryButton = alert.addButton(withTitle: prompt.guidance.actionTitle)
        primaryButton.keyEquivalent = "\r"
        primaryButton.keyEquivalentModifierMask = []

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []

        return alert.runModal() == .alertFirstButtonReturn
    }

    func runReplayBufferConsentAlert() -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Enable Replay Buffer?"
        alert.informativeText =
            "Luxel will continuously capture your display in the background so it can save recent "
            + "moments on demand. Clips are saved only when you choose Clip Replay Buffer."

        let primaryButton = alert.addButton(withTitle: "Enable Replay Buffer")
        primaryButton.keyEquivalent = "\r"
        primaryButton.keyEquivalentModifierMask = []

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []

        return alert.runModal() == .alertFirstButtonReturn
    }

    func startNotchSurface() {
        model.refreshNotchDisplays()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.refreshPermissions()
            refreshNotchSurface()
        }
        notchDisplayTask = Task { @MainActor [weak model] in
            await model?.watchNotchDisplayUpdates()
        }
        notchInteractionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.watchNotchInteractions(
                openEditor: { [weak self] fileURL in
                    self?.windowPresenter.openEditor(fileURL: fileURL)
                },
                openSettings: { [weak self] in
                    self?.windowPresenter.openSettings()
                },
                showAreaCapturePicker: { [weak self] in
                    self?.showNotchAreaCapturePicker()
                }
            )
        }
        refreshNotchSurface()
    }

    func refreshNotchSurface() {
        notchSurfaceRefreshTask?.cancel()
        notchSurfaceRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.refreshNotchSurface(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
    }

    func showNotchAreaCapturePicker() {
        showNotchCapturePicker(recordingActionID: .recordArea)
    }

    func showNotchCapturePicker(
        recordingActionID: NotchActivityActionID?
    ) {
        model.refreshCameraDevices()
        let settings = model.settings
        let canRecordAudio = model.microphoneStatus == .authorized
        let canCaptureKeystrokes = model.inputMonitoringStatus == .authorized
        let quickRecording = model.cropperQuickRecordingConfiguration()
        let selectionPresets = model.cropperSelectionPresetConfiguration()
        let restoredSelection = model.cropperRestoreSelectionConfiguration()
        let recordingOptions = (
            recordAudio: model.captureCapabilities.microphoneTrackAvailable,
            captureKeystrokes: settings.keystrokeOverlayEnabled,
            loupeAlwaysOn: settings.loupeAlwaysOn,
            dimOtherDisplays: settings.dimOtherDisplays
        )
        cropperPanelController.show(
            countdownDuration: settings.defaultCountdown,
            stopAfterDuration: settings.lastStopAfter,
            canRecordAudio: canRecordAudio,
            canCaptureKeystrokes: canCaptureKeystrokes,
            cameraConfiguration: model.cropperCameraConfiguration(),
            quickRecordingConfiguration: quickRecording,
            selectionPresetConfiguration: selectionPresets,
            restoreSelectionConfiguration: restoredSelection,
            recordAudio: recordingOptions.recordAudio,
            captureKeystrokes: recordingOptions.captureKeystrokes,
            loupeAlwaysOn: recordingOptions.loupeAlwaysOn,
            dimOtherDisplays: recordingOptions.dimOtherDisplays,
            showsNotificationReminder: false,
            onCountdownDurationChange: { [weak self] in self?.updateCropperCountdown($0) },
            onStopAfterDurationChange: { [weak self] in self?.updateCropperStopAfter($0) },
            onRecordAudioChange: { [weak self] in self?.updateCropperAudio($0) },
            onCaptureKeystrokesChange: { [weak self] isEnabled in
                self?.model.settings.keystrokeOverlayEnabled = isEnabled
                self?.model.saveSettings()
            },
            onCameraSelectionChange: { [weak self] in self?.updateCropperCamera($0) },
            onCameraPreviewStyleChange: { [weak self] in self?.updateCropperCameraStyle($0) },
            onNotificationReminderDismiss: { [weak model] in model?.dismissNotificationReminder() },
            onQuickSelect: { [weak model] draft, presetID in
                Task {
                    await model?.startQuickRecording(
                        from: draft,
                        presetID: presetID,
                        notchRecordingActionID: recordingActionID
                    )
                }
            },
            onSelect: { [weak model] draft in
                Task {
                    await model?.startRecording(
                        from: draft,
                        notchRecordingActionID: recordingActionID
                    )
                }
            }
        )
    }

    func updateCropperCountdown(_ duration: TimeInterval?) {
        updateCropperSettings { $0.defaultCountdown = duration }
    }

    func updateCropperStopAfter(_ duration: TimeInterval?) {
        updateCropperSettings { $0.lastStopAfter = duration }
    }

    func updateCropperAudio(_ isEnabled: Bool) {
        guard !isEnabled || model.microphoneStatus == .authorized else {
            presentPermissionPrompt(for: .microphone)
            return
        }
        updateCropperSettings { $0.recordAudio = isEnabled }
    }

    func updateCropperSettings(_ update: (inout AppSettings) -> Void) {
        update(&model.settings)
        model.saveSettings()
    }

    func updateCropperCamera(_ deviceID: String?) {
        Task { await model.setCameraDeviceFromCropper(deviceID) }
    }

    func updateCropperCameraStyle(_ style: CameraPreviewStyle) {
        Task { await model.setCameraPreviewStyleFromCropper(style) }
    }

    var isStatusItemButtonConfigured: Bool {
        guard let button = statusItem.button else {
            return false
        }

        return button.target === self && button.action == #selector(handleStatusItemClick)
    }

    func togglePopover() {
        guard statusItem.button != nil else {
            return
        }

        if isPopoverShown {
            closePopover()
        } else if shouldSuppressRecentPopoverOpen {
            suppressNextPopoverOpenUntil = nil
        } else {
            openPopover()
        }
    }

    var isPopoverShown: Bool {
        menuPanel?.isVisible == true
    }

    var shouldSuppressRecentPopoverOpen: Bool {
        guard let suppressNextPopoverOpenUntil else {
            return false
        }

        if suppressNextPopoverOpenUntil > Date() {
            return true
        }

        self.suppressNextPopoverOpenUntil = nil
        return false
    }

    var isMouseOverStatusItemButton: Bool {
        guard let button = statusItem.button else {
            return false
        }

        let buttonFrame = statusItemButtonFrame(relativeTo: button)
            .insetBy(dx: -4, dy: -4)
        return buttonFrame.contains(NSEvent.mouseLocation)
    }
}
