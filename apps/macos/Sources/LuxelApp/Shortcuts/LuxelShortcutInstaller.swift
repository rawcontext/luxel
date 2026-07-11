import Foundation
import LuxelCore
import SwiftUI

struct LuxelShortcutInstaller: View {
    let model: LuxelMenuModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let openRecording: @MainActor @Sendable (URL) -> Void

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
            .onChange(of: model.settings.clipReplayBufferShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.pauseKeystrokeCaptureShortcut) {
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
            toggleRecordingShortcutRegistration(),
            activeWindowRecordingShortcutRegistration(),
            fullscreenRecordingShortcutRegistration(),
            audioOnlyRecordingShortcutRegistration(),
            quickRecordLastShortcutRegistration(),
            clipReplayBufferShortcutRegistration(),
            pauseKeystrokeCaptureShortcutRegistration()
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
                canRecordAudio: model.microphoneStatus == .authorized,
                canCaptureKeystrokes: model.inputMonitoringStatus == .authorized,
                quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
                selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
                restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
                recordAudio: model.captureCapabilities.microphoneTrackAvailable,
                captureKeystrokes: model.settings.keystrokeOverlayEnabled,
                loupeAlwaysOn: model.settings.loupeAlwaysOn,
                dimOtherDisplays: model.settings.dimOtherDisplays,
                showsNotificationReminder: false,
                onCountdownDurationChange: saveDefaultCountdown,
                onStopAfterDurationChange: saveStopAfterDuration,
                onRecordAudioChange: saveRecordAudio,
                onCaptureKeystrokesChange: saveCaptureKeystrokes,
                onNotificationReminderDismiss: model.dismissNotificationReminder,
                onQuickSelect: startQuickRecording,
                onSelect: startRecording
            )
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
                  model.fullscreenCaptureTarget != nil
            else {
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

    private func clipReplayBufferShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.clipReplayBufferShortcut) {
            guard model.replayBufferMenuPresentation.canClip else {
                return
            }

            Task {
                await model.clipReplayBufferFromMenu(openRecording: openRecording)
            }
        }
    }

    private func pauseKeystrokeCaptureShortcutRegistration() -> LuxelShortcutRegistration {
        LuxelShortcutRegistration(rawShortcut: model.settings.pauseKeystrokeCaptureShortcut) {
            model.toggleKeystrokeCapturePause()
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

    private func saveCaptureKeystrokes(_ isEnabled: Bool) {
        model.settings.keystrokeOverlayEnabled = isEnabled
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
