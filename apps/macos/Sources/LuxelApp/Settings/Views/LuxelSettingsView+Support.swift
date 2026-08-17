import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    var unavailableCameraDeviceID: String? {
        guard let cameraDeviceID = model.settings.cameraDeviceID,
              !model.cameraDevices.contains(where: { $0.id == cameraDeviceID })
        else {
            return nil
        }

        return cameraDeviceID
    }

    var visibleShortcutCommands: [LuxelShortcutSettingsCommand] {
        let searchText = shortcutSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return shortcutCommands.filter { $0.matchesSearch(searchText) }
    }

    var shortcutCommands: [LuxelShortcutSettingsCommand] {
        [
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "select-area", title: "Select Area",
                    detail: "Choose a screen area to record.", group: "Recording"
                ),
                selection: $model.settings.triggerCropperShortcut,
                presets: AppKeyboardShortcutPresets.capture
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "toggle-recording", title: "Toggle Recording",
                    detail: "Start or stop recording.", group: "Recording"
                ),
                selection: $model.settings.toggleRecordingShortcut,
                presets: AppKeyboardShortcutPresets.toggleRecording
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "record-active-window", title: "Record Active Window",
                    detail: "Record the frontmost window.", group: "Recording"
                ),
                selection: $model.settings.recordActiveWindowShortcut,
                presets: AppKeyboardShortcutPresets.recordActiveWindow
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "record-fullscreen", title: "Record Fullscreen",
                    detail: "Record the current display.", group: "Recording"
                ),
                selection: $model.settings.recordFullscreenShortcut,
                presets: AppKeyboardShortcutPresets.recordFullscreen
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "audio-only", title: "Audio Only",
                    detail: "Start an audio-only recording.", group: "Recording"
                ),
                selection: $model.settings.audioOnlyRecordingShortcut,
                presets: AppKeyboardShortcutPresets.audioOnlyRecording
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "quick-record-last", title: "Quick Record Last",
                    detail: "Record the previous capture target with quick export settings.",
                    group: "Recording"
                ),
                selection: $model.settings.quickRecordLastShortcut,
                presets: AppKeyboardShortcutPresets.quickRecordLast
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "clip-replay-buffer", title: "Clip Replay Buffer",
                    detail: "Save the recent replay buffer.", group: "Replay Buffer"
                ),
                selection: $model.settings.clipReplayBufferShortcut,
                presets: AppKeyboardShortcutPresets.clipReplayBuffer
            ),
            shortcutCommand(
                ShortcutCommandMetadata(
                    id: "pause-keystroke-capture", title: "Pause Keystroke Capture",
                    detail: "Pause or resume keystroke capture during a recording.",
                    group: "Recording"
                ),
                selection: $model.settings.pauseKeystrokeCaptureShortcut,
                presets: []
            )
        ]
    }

    func shortcutCommand(
        _ metadata: ShortcutCommandMetadata,
        selection: Binding<String>,
        presets: [AppKeyboardShortcut]
    ) -> LuxelShortcutSettingsCommand {
        LuxelShortcutSettingsCommand(
            id: metadata.id,
            title: metadata.title,
            detail: metadata.detail,
            searchGroup: metadata.group,
            selection: selection,
            defaultRawValue: presets.first?.rawValue ?? ""
        )
    }

    @ViewBuilder
    var recordingFrameRateSettings: some View {
        SettingsRow("Frame Rate") {
            HStack(spacing: 6) {
                TextField(
                    "FPS",
                    value: recordingFrameRateSelection,
                    formatter: recordingFrameRateFormatter
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .disabled(model.settings.matchDisplayFrameRate)
                .opacity(model.settings.matchDisplayFrameRate ? 0.45 : 1)
                .help("Choose the recording frame rate from 1 to 120 FPS.")

                Text("FPS")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .luxelGlassFieldBackground(cornerRadius: 13)
        }
        .help("Choose a fixed frame rate or match the display refresh rate.")
    }

    var matchDisplayFrameRateSelection: Binding<Bool> {
        Binding {
            model.settings.matchDisplayFrameRate
        } set: { matchesDisplay in
            model.settings.matchDisplayFrameRate = matchesDisplay
            recordingFrameRateMessage = nil
        }
    }

    var recordingFrameRateSelection: Binding<Int> {
        Binding {
            model.settings.recordingFrameRate.framesPerSecond
        } set: { frameRate in
            do {
                try model.settings.setRecordingFrameRate(frameRate)
                recordingFrameRateMessage = nil
            } catch {
                recordingFrameRateMessage = "Use a whole number from 1 to 120 FPS."
            }
        }
    }

    var recordingFrameRateFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: AppSettings.recordingFrameRateRange.lowerBound)
        formatter.maximum = NSNumber(value: AppSettings.recordingFrameRateRange.upperBound)
        return formatter
    }

    func openRecording(_ url: URL) {
        openEditorWindow()

        Task {
            model.configureEditor(editorModel)
            await editorModel.open(
                fileURL: url,
                outputDirectory: model.settings.recordingsDirectory,
                outputDirectoryBookmark: model.settings.recordingsDirectoryBookmark,
                transcriptSourceContext: model.transcriptSourceContext(for: url)
            )
        }
    }

    func openEditorWindow() {
        if let openEditorWindowOverride {
            openEditorWindowOverride()
        } else {
            openWindow(id: LuxelEditorScene.id)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

struct ShortcutCommandMetadata {
    let id: String
    let title: String
    let detail: String
    let group: String
}
