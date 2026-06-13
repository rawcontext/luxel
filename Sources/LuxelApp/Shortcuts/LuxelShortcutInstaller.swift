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
            .onChange(of: model.settings.audioOnlyRecordingShortcut) {
                configureShortcut()
            }
            .onChange(of: model.settings.quickRecordLastShortcut) {
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
                        audioLevelConfiguration: model.cropperAudioLevelConfiguration()
                    ) { draft in
                        Task {
                            await model.startRecording(from: draft)
                        }
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
                            await model.startRecordingFromLastCapture()
                        }
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
                        await model.startQuickRecordingFromLastCapture()
                    }
                }
            ]
        )
    }
}
