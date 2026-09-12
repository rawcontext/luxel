import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    @ViewBuilder
    var outputSettingsForm: some View {
        SettingsIslandGroup(
            "Recordings",
            footer: "Choose where Luxel saves recordings and how the editor behaves after export."
        ) {
            SettingsRow("Folder") {
                Button {
                    model.chooseRecordingsDirectory()
                } label: {
                    SettingsCapsuleButtonLabel(
                        model.recordingsDirectorySummary,
                        systemImage: "folder"
                    )
                }
                .buttonStyle(.plain)
                .help(
                    LuxelLocalization.format(
                        "Choose where new recordings are saved. Current: %@", model.recordingsDirectoryPath)
                )
            }

            LuxelGlassRowDivider()

            settingsToggleRow("Loop Exports", isOn: $model.settings.loopExports)
                .help("Make exported videos loop when the format supports it.")

            LuxelGlassRowDivider()

            settingsToggleRow("Confirm Discard", isOn: $model.settings.confirmDiscard)
                .help("Ask before closing an editor with unsaved changes.")
        }
    }

    @ViewBuilder
    var presetSettingsForm: some View {
        ExportPresetSettingsSection(settings: $model.settings)

        SettingsIslandGroup("Cropper") {
            settingsToggleRow("Always Show Loupe", isOn: $model.settings.loupeAlwaysOn)
                .help("Keep the precision loupe visible while selecting an area.")

            LuxelGlassRowDivider()

            settingsToggleRow("Dim Other Displays", isOn: $model.settings.dimOtherDisplays)
                .help("Darken inactive displays while choosing a capture area.")

            LuxelGlassRowDivider()

            settingsToggleRow("Restore Last Selection", isOn: $model.settings.restoreLastSelection)
                .help("Start area selection from your previous capture region.")
        }

        CaptureSizePresetSettingsSection(settings: $model.settings)
    }

    @ViewBuilder
    var shortcutSettingsForm: some View {
        SettingsIslandGroup("Keyboard") {
            settingsToggleRow("Keyboard Shortcuts", isOn: $model.settings.enableShortcuts)
                .help("Enable Luxel's global recording shortcuts.")
        }

        SettingsIslandGroup(
            "Commands",
            footer: "Shortcut conflicts are shown inline when a system shortcut uses the same keys."
        ) {
            LuxelShortcutSearchField(text: $shortcutSearchText)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .help("Filter shortcuts by command name or group.")

            LuxelShortcutSettingsTable(
                commands: visibleShortcutCommands,
                allCommands: shortcutCommands,
                isEnabled: model.settings.enableShortcuts,
                conflictDetector: shortcutConflictDetector,
                editingCommandID: $editingShortcutCommandID
            )
            .padding(.bottom, 12)
            .help("Edit, clear, or reset Luxel keyboard shortcuts.")
        }
    }

    @ViewBuilder
    var replayBufferSettingsForm: some View {
        let isConfigured = model.settings.replayBufferConfiguration != nil

        SettingsIslandGroup(
            "Replay Buffer",
            footer:
                "Replay buffer uses screen capture permission and stays visible in the menu bar while active."
        ) {
            settingsToggleRow("Enable Replay Buffer", isOn: replayBufferEnabled)
                .help("Continuously keep recent screen video available for clipping.")

            LuxelGlassRowDivider()

            settingsToggleRow(
                "Always Show Replay Buffer Island",
                isOn: $model.settings.alwaysShowReplayBufferIsland
            )
            .help("Keep the replay buffer controls visible in the menu even when replay buffer is off.")

            LuxelGlassRowDivider()

            SettingsRow("Length") {
                SettingsMenuPicker(
                    selection: replayBufferLengthSelection,
                    options: Self.replayBufferLengths
                ) { seconds in
                    replayBufferLengthLabel(seconds)
                }
            }
            .disabled(model.replayBufferState == .clipping)
            .help("Choose how much recent recording history to keep.")

            LuxelGlassRowDivider()

            SettingsRow("Source") {
                settingsValueText("Display with Cursor")
            }
            .help("Replay buffer will capture the display and cursor.")

            LuxelGlassRowDivider()

            SettingsRow("Frame Rate") {
                SettingsMenuPicker(
                    selection: replayBufferFrameRateSelection,
                    options: Self.replayBufferFrameRates
                ) { frameRate in
                    "\(frameRate) FPS"
                }
            }
            .disabled(!isConfigured)
            .opacity(isConfigured ? 1 : 0.45)
            .help("Choose the frame rate for replay buffer clips.")

            LuxelGlassRowDivider()

            settingsToggleRow("Include System Audio", isOn: replayBufferSystemAudioSelection)
                .disabled(!isConfigured)
                .help("Include Mac audio in replay buffer clips.")

            LuxelGlassRowDivider()

            settingsToggleRow("Start Replay When Luxel Launches", isOn: replayBufferResumeOnLaunch)
                .help("Start the replay buffer automatically when Luxel opens.")

            LuxelGlassRowDivider()

            SettingsRow("Clip Opens In") {
                SettingsMenuPicker(
                    selection: $model.settings.replayClipDestination,
                    options: Array(ReplayClipDestination.allCases)
                ) { destination in
                    destination.label
                }
            }
            .disabled(!isConfigured)
            .opacity(isConfigured ? 1 : 0.45)
            .help("Choose what happens after saving a replay clip.")
        }
    }

}
