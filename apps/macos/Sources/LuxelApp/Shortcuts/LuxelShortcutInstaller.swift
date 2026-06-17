import Foundation
import LuxelCore
import SwiftUI

struct LuxelShortcutInstaller: View {
    let model: LuxelMenuModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let openRecording: (URL) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                configureShortcut()
            }
            .onChange(of: model.settings.enableShortcuts) {
                configureShortcut()
            }
            .onChange(of: model.settings.triggerCropperShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.toggleRecordingShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.recordActiveWindowShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.recordFullscreenShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.audioOnlyRecordingShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.quickRecordLastShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.captureScreenshotShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.screenshotActiveWindowShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.screenshotFullscreenShortcut) {
                configureShortcut()
            }
    }

    private func configureShortcut() {
        shortcutController.configure(
            enabled: model.settings.enableShortcuts,
            registrations: shortcutRegistrations
        )
    }

    private var shortcutRegistrations: [LuxelShortcutRegistration] {
        [
            cropperShortcutRegistration(),
            screenshotShortcutRegistration(),
            activeWindowScreenshotShortcutRegistration(),
            fullscreenScreenshotShortcutRegistration(),
            toggleRecordingShortcutRegistration(),
            activeWindowRecordingShortcutRegistration(),
            fullscreenRecordingShortcutRegistration(),
            audioOnlyRecordingShortcutRegistration(),
            quickRecordLastShortcutRegistration()
        ]
    }

    private func cropperShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.triggerCropperShortcut) {
            guard model.canSelectArea else {
                return
            }

            cropperPanelController.show(
                countdownDuration: model.settings.defaultCountdown,
                stopAfterDuration: model.settings.lastStopAfter,
                audioLevelConfiguration: model.cropperAudioLevelConfiguration(),
                quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
                selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
                restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
                recordAudio: model.captureCapabilities.microphoneTrackAvailable,
                loupeAlwaysOn: model.settings.loupeAlwaysOn,
                dimOtherDisplays: model.settings.dimOtherDisplays,
                showsNotificationReminder: model.settings.notificationReminder,
                onCountdownDurationChange: saveDefaultCountdown,
                onStopAfterDurationChange: saveStopAfterDuration,
                onRecordAudioChange: saveRecordAudio,
                onNotificationReminderDismiss: model.dismissNotificationReminder,
                onQuickSelect: startQuickRecording,
                onSelect: startRecording
            )
        }
    }

    private func screenshotShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.captureScreenshotShortcut) {
            guard model.canSelectArea else {
                return
            }

            cropperPanelController.show(
                initialMode: .photo,
                countdownDuration: model.settings.defaultCountdown,
                stopAfterDuration: model.settings.lastStopAfter,
                audioLevelConfiguration: model.cropperAudioLevelConfiguration(),
                quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
                selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
                restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
                recordAudio: model.captureCapabilities.microphoneTrackAvailable,
                loupeAlwaysOn: model.settings.loupeAlwaysOn,
                dimOtherDisplays: model.settings.dimOtherDisplays,
                showsNotificationReminder: model.settings.notificationReminder,
                onCountdownDurationChange: saveDefaultCountdown,
                onStopAfterDurationChange: saveStopAfterDuration,
                onRecordAudioChange: saveRecordAudio,
                onNotificationReminderDismiss: model.dismissNotificationReminder,
                onCaptureScreenshot: captureScreenshot,
                onQuickSelect: startQuickRecording,
                onSelect: startRecording
            )
        }
    }

    private func activeWindowScreenshotShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.screenshotActiveWindowShortcut) {
            guard model.canSelectArea else {
                return
            }

            Task {
                await model.captureActiveWindowScreenshot()
            }
        }
    }

    private func fullscreenScreenshotShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.screenshotFullscreenShortcut) {
            guard model.screenRecordingStatus == .authorized,
                  model.fullscreenCaptureTarget != nil else {
                return
            }

            Task {
                await model.captureFullscreenScreenshot()
            }
        }
    }

    private func toggleRecordingShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.toggleRecordingShortcut) {
            Task {
                await toggleRecording()
            }
        }
    }

    private func activeWindowRecordingShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.recordActiveWindowShortcut) {
            guard model.canSelectArea else {
                return
            }

            Task {
                await model.startActiveWindowRecording()
            }
        }
    }

    private func fullscreenRecordingShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.recordFullscreenShortcut) {
            guard model.screenRecordingStatus == .authorized,
                  model.fullscreenCaptureTarget != nil else {
                return
            }

            Task {
                await model.startFullscreenRecording()
            }
        }
    }

    private func audioOnlyRecordingShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.audioOnlyRecordingShortcut) {
            Task {
                if model.hasActiveAudioOnlyRecording {
                    _ = await model.stopRecording()
                } else if model.canUseAudioOnlyButton {
                    await model.startAudioOnlyRecording()
                }
            }
        }
    }

    private func quickRecordLastShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.quickRecordLastShortcut) {
            guard model.canUseQuickRecordLastButton else {
                return
            }

            Task {
                await model.startQuickRecordingFromLastCapture(entryPoint: .quickRecordLastShortcut)
            }
        }
    }

    private func saveDefaultCountdown(_ duration: TimeInterval?) {
        model.settings.defaultCountdown = duration
        model.saveSettings()
    }

    private func saveStopAfterDuration(_ duration: TimeInterval?) {
        model.settings.lastStopAfter = duration
        model.saveSettings()
    }

    private func saveRecordAudio(_ isEnabled: Bool) {
        guard !isEnabled || model.microphoneStatus == .authorized else {
            model.presentPermissionPrompt(for: .microphone)
            return
        }

        model.settings.recordAudio = isEnabled
        model.saveSettings()
    }

    private func startQuickRecording(_ draft: CaptureSelectionDraft, presetID: UUID) {
        Task {
            await model.startQuickRecording(from: draft, presetID: presetID)
        }
    }

    private func startRecording(_ draft: CaptureSelectionDraft) {
        Task {
            await model.startRecording(from: draft)
        }
    }

    private func captureScreenshot(_ draft: CaptureSelectionDraft) {
        Task {
            await model.captureScreenshot(from: draft)
        }
    }

    private func toggleRecording() async {
        if model.hasActiveRecording {
            guard let stopAction = await model.stopRecording() else {
                return
            }

            if case .openEditor(let fileURL) = stopAction {
                openRecording(fileURL)
            }
        } else if model.canUseRecordAgainButton {
            await model.startRecordingFromLastCapture(entryPoint: .toggleRecordingShortcut)
        }
    }
}
