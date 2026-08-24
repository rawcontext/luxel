import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    @ViewBuilder
    var notificationsSettingsForm: some View {
        SettingsIslandGroup(
            notificationString(
                "settings.notifications.system.title",
                "System Notifications"
            ),
            footer: notificationPermissionFooter
        ) {
            settingsToggleRow(
                notificationString(
                    "settings.notifications.allow",
                    "Allow Notifications"
                ),
                isOn: appNotificationsSelection
            )
            .help(
                notificationString(
                    "settings.notifications.allowHelp",
                    "Allow Luxel to deliver speech prompts and export completion alerts."
                )
            )

            LuxelGlassRowDivider()

            settingsToggleRow(
                notificationString(
                    "settings.notifications.timeSensitive",
                    "Time Sensitive Speech Alerts"
                ),
                isOn: timeSensitiveNotificationsSelection
            )
            .help(
                notificationString(
                    "settings.notifications.timeSensitiveHelp",
                    "Open macOS settings for Time Sensitive speech alerts."
                )
            )
        }

        SettingsIslandGroup(
            notificationString(
                "settings.notifications.types.title",
                "Notification Types"
            )
        ) {
            settingsToggleRow(
                notificationString(
                    "settings.notifications.speechDetection",
                    "Speech Detection Prompts"
                ),
                isOn: speechDetectionPromptsSelection
            )
            .help(
                notificationString(
                    "settings.notifications.speechDetectionHelp",
                    "Notify you after Luxel detects sustained speech."
                )
            )

            LuxelGlassRowDivider()

            settingsToggleRow(
                notificationString(
                    "settings.notifications.exportComplete",
                    "Export Completed"
                ),
                isOn: exportCompletionNotificationsSelection
            )
            .help(
                notificationString(
                    "settings.notifications.exportCompleteHelp",
                    "Notify you when an editor export finishes."
                )
            )
        }
        .task {
            await model.refreshAppNotificationSettings()
        }
    }

    var exportCompletionNotificationsSelection: Binding<Bool> {
        Binding {
            model.settings.exportCompletionNotificationsEnabled
        } set: { isEnabled in
            model.settings.exportCompletionNotificationsEnabled = isEnabled
            if isEnabled {
                Task { await model.setAppNotificationsEnabled(true) }
            }
        }
    }
}
