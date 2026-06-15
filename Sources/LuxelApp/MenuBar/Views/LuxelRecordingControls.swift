import AppKit
import Foundation
import SwiftUI

struct LuxelRecordingControls: View {
    let model: LuxelMenuModel
    let cropperPanelController: LuxelCropperPanelController
    let openRecording: (URL) -> Void

    var body: some View {
        Button {
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
                } else {
                    startAfterDismissingMenu {
                        await model.startRecordingFromSelectedTarget()
                    }
                }
            }
        } label: {
            Label(model.recordButtonTitle, systemImage: model.recordButtonSystemImage)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canUseRecordButton)

        Button {
            Task {
                await model.startQuickRecordingFromSelectedTarget()
            }
        } label: {
            Label("Quick Record", systemImage: "bolt.circle")
        }
        .disabled(!model.canUseQuickRecordButton)

        Button {
            Task {
                await model.startAudioOnlyRecording()
            }
        } label: {
            Label("Record Audio Only", systemImage: "waveform")
        }
        .disabled(!model.canUseAudioOnlyButton)

        Button {
            Task {
                await model.captureScreenshotFromSelectedTarget()
            }
        } label: {
            Label("Capture Screenshot", systemImage: "camera")
        }
        .disabled(!model.canCaptureScreenshot)

        Button {
            Task {
                await model.startRecordingFromLastCapture()
            }
        } label: {
            Label("Record Again", systemImage: "arrow.clockwise")
        }
        .disabled(!model.canUseRecordAgainButton)

        Button {
            Task {
                await model.startQuickRecordingFromLastCapture()
            }
        } label: {
            Label("Quick Record Last", systemImage: "bolt.circle")
        }
        .disabled(!model.canUseQuickRecordLastButton)

        if model.canPauseOrResumeRecording {
            Button {
                Task {
                    await model.pauseOrResumeRecording()
                }
            } label: {
                Label(model.pauseResumeButtonTitle, systemImage: model.pauseResumeButtonSystemImage)
            }
            .disabled(!model.canUsePauseResumeButton)
        }

        Button {
            model.refreshCameraDevices()
            cropperPanelController.show(
                countdownDuration: model.settings.defaultCountdown,
                stopAfterDuration: model.settings.lastStopAfter,
                audioLevelConfiguration: model.cropperAudioLevelConfiguration(),
                cameraConfiguration: model.cropperCameraConfiguration(),
                quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
                selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
                restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
                loupeAlwaysOn: model.settings.loupeAlwaysOn,
                dimOtherDisplays: model.settings.dimOtherDisplays,
                showsNotificationReminder: model.settings.notificationReminder,
                onCountdownDurationChange: { duration in
                    model.settings.defaultCountdown = duration
                    model.saveSettings()
                },
                onStopAfterDurationChange: { duration in
                    model.settings.lastStopAfter = duration
                    model.saveSettings()
                },
                onCameraSelectionChange: { deviceID in
                    Task {
                        await model.setCameraDeviceFromCropper(deviceID)
                    }
                },
                onCameraPreviewStyleChange: { style in
                    Task {
                        await model.setCameraPreviewStyleFromCropper(style)
                    }
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
        } label: {
            Label("Select Area", systemImage: "crop")
        }
        .disabled(!model.canSelectArea)
    }

    private func startAfterDismissingMenu(_ action: @escaping @MainActor () async -> Void) {
        Task { @MainActor in
            let menuWindow = NSApplication.shared.keyWindow
            await Task.yield()
            menuWindow?.orderOut(nil)
            await Task.yield()
            await action()
        }
    }
}
