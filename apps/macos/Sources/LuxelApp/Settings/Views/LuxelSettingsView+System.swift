import AppKit
import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    @ViewBuilder
    var notchSettingsForm: some View {
        let notchStatus = model.notchSurfaceStatusPresentation

        SettingsIslandGroup(
            "Notch Surface",
            footer: notchStatus.showsStatus ? notchStatus.detailText : nil
        ) {
            if notchStatus.showsStatus {
                SettingsRow("Status") {
                    settingsValueText(notchStatus.statusText)
                }
                .help("Shows whether the notch surface is available.")

                LuxelGlassRowDivider()
            }

            settingsToggleRow("Enable Notch Surface", isOn: notchSurfaceEnabled)
                .help("Show recording controls around the built-in notch.")

            LuxelGlassRowDivider()

            settingsToggleRow("Idle Quick Actions", isOn: notchIdleHoverActionsEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show quick actions when hovering near the notch while idle.")

            LuxelGlassRowDivider()

            settingsToggleRow("Recording Waveform", isOn: notchWaveformEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Show an audio waveform on the notch surface while recording.")

            LuxelGlassRowDivider()

            SettingsRow("Auto Collapse") {
                SettingsMenuPicker(
                    selection: notchAutoCollapseSecondsSelection,
                    options: Self.notchAutoCollapseDurations
                ) { seconds in
                    notchAutoCollapseLabel(seconds)
                }
            }
            .disabled(!model.settings.notchSurfaceSettings.isEnabled)
            .opacity(model.settings.notchSurfaceSettings.isEnabled ? 1 : 0.45)
            .help("Choose how quickly expanded notch controls collapse.")

            LuxelGlassRowDivider()

            settingsToggleRow("Floating HUD Fallback", isOn: notchFloatingHUDFallbackEnabled)
                .disabled(!model.settings.notchSurfaceSettings.isEnabled)
                .help("Use a floating HUD when notch controls are unavailable.")
        }
    }

    func settingsValueText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    var commandLineToolSettingsForm: some View {
        CommandLineToolSettingsSection(model: model)
    }

    @ViewBuilder
    var systemSettingsForm: some View {
        SettingsIslandGroup("Menu Bar") {
            settingsToggleRow("Show Time in Menu Bar", isOn: $model.settings.showTimeInMenuBar)
                .help("Show elapsed recording time in the menu bar.")

            if model.settings.notchSurfaceSettings.isEnabled {
                LuxelGlassRowDivider()

                settingsToggleRow("Hide Menu Bar Icon", isOn: $model.settings.hideMenuBarIcon)
                    .help("Hide Luxel from the menu bar while the notch surface is enabled.")
            }

            LuxelGlassRowDivider()

            settingsToggleRow("Remind About Notifications", isOn: $model.settings.notificationReminder)
                .help("Remind you to silence notifications before recording.")
        }

        SettingsIslandGroup("Startup") {
            settingsToggleRow("Launch at Login", isOn: $model.launchAtLogin)
                .help("Open Luxel automatically when you sign in.")
        }

        updatesSettingsGroup

        SettingsIslandGroup("About") {
            SettingsRow("App") {
                settingsValueText(model.appMetadata.displayName)
            }
            .help("Shows the application name.")

            LuxelGlassRowDivider()

            SettingsRow("Version") {
                settingsValueText(model.appMetadata.versionSummary)
            }
            .help("Shows the installed version and build.")

            LuxelGlassRowDivider()

            SettingsRow {
                Button {
                    isShowingAcknowledgements = true
                } label: {
                    SettingsCapsuleButtonLabel("Acknowledgements", systemImage: "doc.text")
                }
                .buttonStyle(.plain)
                .help("View third-party codec acknowledgements.")
            }
        }

        if !model.appMetadata.copyright.isEmpty {
            LuxelGlassSectionFooter(model.appMetadata.copyright)
                .padding(.leading, 6)
        }
    }

    @ViewBuilder
    var updatesSettingsGroup: some View {
        let updatePresentation = updateSettingsPresentation

        SettingsIslandGroup("Updates", footer: updatePresentation.networkPolicyText) {
            SettingsRow("Current Version") {
                settingsValueText(model.appMetadata.versionSummary)
            }
            .help("Shows the installed Luxel version.")

            LuxelGlassRowDivider()

            SettingsRow("Status") {
                settingsValueText(updatePresentation.statusText)
            }
            .help("Shows the current update availability.")

            if updatePresentation.showsDeveloperIDUpdateControls {
                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Check Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyCheckForUpdates
                )
                .help("Let Luxel periodically check for updates.")

                LuxelGlassRowDivider()

                settingsToggleRow(
                    "Install Automatically",
                    isOn: $model.settings.updatePreferences.automaticallyDownloadAndInstall
                )
                .disabled(!updatePresentation.automaticInstallToggleEnabled)
                .help("Download and install updates without asking.")

                LuxelGlassRowDivider()

                SettingsRow("Channel") {
                    SettingsMenuPicker(
                        selection: $model.settings.updatePreferences.channel,
                        options: Array(UpdateChannel.allCases)
                    ) { channel in
                        channel.label
                    }
                }
                .help("Choose which update channel Luxel checks.")

                LuxelGlassRowDivider()

                SettingsRow {
                    Button {
                    } label: {
                        SettingsCapsuleButtonLabel("Check Now", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .disabled(!updatePresentation.canCheckNow)
                    .opacity(updatePresentation.canCheckNow ? 1 : 0.45)
                    .help(updatePresentation.checkNowHelp)
                }
            }
        }
    }

}
