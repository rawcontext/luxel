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
                    await model.startRecordingFromSelectedTarget()
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
            cropperPanelController.show(
                stopAfterDuration: model.settings.lastStopAfter,
                audioLevelConfiguration: model.cropperAudioLevelConfiguration(),
                onStopAfterDurationChange: { duration in
                    model.settings.lastStopAfter = duration
                    model.saveSettings()
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
}
