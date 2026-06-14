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
            registrations: [
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
                        showsNotificationReminder: model.settings.notificationReminder,
                        onCountdownDurationChange: { duration in
                            model.settings.defaultCountdown = duration
                            model.saveSettings()
                        },
                        onStopAfterDurationChange: { duration in
                            model.settings.lastStopAfter = duration
                            model.saveSettings()
                        },
                        onNotificationReminderDismiss: {
                            model.dismissNotificationReminder()
                        },
                        onQuickSelect: { draft, presetID in
                            Task {
                                await model.startQuickRecording(from: draft, presetID: presetID)
                            }
                        }
                    ) { draft in
                        Task {
                            await model.startRecording(from: draft)
                        }
                    }
                },
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
                        showsNotificationReminder: model.settings.notificationReminder,
                        onCountdownDurationChange: { duration in
                            model.settings.defaultCountdown = duration
                            model.saveSettings()
                        },
                        onStopAfterDurationChange: { duration in
                            model.settings.lastStopAfter = duration
                            model.saveSettings()
                        },
                        onNotificationReminderDismiss: {
                            model.dismissNotificationReminder()
                        },
                        onCaptureScreenshot: { draft in
                            Task {
                                await model.captureScreenshot(from: draft)
                            }
                        },
                        onQuickSelect: { draft, presetID in
                            Task {
                                await model.startQuickRecording(from: draft, presetID: presetID)
                            }
                        }
                    ) { draft in
                        Task {
                            await model.startRecording(from: draft)
                        }
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.screenshotActiveWindowShortcut) {
                    guard model.canSelectArea else {
                        return
                    }

                    Task {
                        await model.captureActiveWindowScreenshot()
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.screenshotFullscreenShortcut) {
                    guard model.screenRecordingStatus == .authorized,
                          model.fullscreenCaptureTarget != nil else {
                        return
                    }

                    Task {
                        await model.captureFullscreenScreenshot()
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.toggleRecordingShortcut) {
                    Task {
                        if model.hasActiveRecording {
                            if let stopAction = await model.stopRecording() {
                                switch stopAction {
                                case .openEditor(let fileURL):
                                    openRecording(fileURL)
                                case .quickExported, .audioRecorded:
                                    break
                                }
                            }
                        } else if model.canUseRecordAgainButton {
                            await model.startRecordingFromLastCapture(entryPoint: .toggleRecordingShortcut)
                        }
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.recordActiveWindowShortcut) {
                    guard model.canSelectArea else {
                        return
                    }

                    Task {
                        await model.startActiveWindowRecording()
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.recordFullscreenShortcut) {
                    guard model.screenRecordingStatus == .authorized,
                          model.fullscreenCaptureTarget != nil else {
                        return
                    }

                    Task {
                        await model.startFullscreenRecording()
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.audioOnlyRecordingShortcut) {
                    Task {
                        if model.hasActiveAudioOnlyRecording {
                            _ = await model.stopRecording()
                        } else if model.canUseAudioOnlyButton {
                            await model.startAudioOnlyRecording()
                        }
                    }
                },
                LuxelShortcutRegistration(rawShortcut: model.settings.quickRecordLastShortcut) {
                    guard model.canUseQuickRecordLastButton else {
                        return
                    }

                    Task {
                        await model.startQuickRecordingFromLastCapture(entryPoint: .quickRecordLastShortcut)
                    }
                }
            ]
        )
    }
}
