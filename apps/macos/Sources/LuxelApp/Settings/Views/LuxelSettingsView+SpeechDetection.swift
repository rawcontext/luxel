import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    var speechDetectionSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsIslandGroup(
                speechDetectionString(
                    "settings.speechDetection.title",
                    "Speech Detection"
                )
            ) {
                settingsToggleRow(
                    speechDetectionString(
                        "settings.speechDetection.toggle",
                        "Notify When Speech Is Detected"
                    ),
                    isOn: speechDetectionPromptsSelection
                )
                .help(
                    speechDetectionString(
                        "settings.speechDetection.help",
                        "Show a recording prompt after Luxel detects sustained speech on the selected microphone."
                    ))

                LuxelGlassRowDivider()

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
            }

            VStack(alignment: .leading, spacing: 2) {
                LuxelGlassSectionFooter(
                    speechDetectionString(
                        "settings.speechDetection.footer",
                        "Luxel analyzes microphone audio on this Mac while it is running. "
                            + "Audio is discarded unless you start recording."
                    ))
                LuxelGlassSectionFooter(notificationPermissionFooter)
                LuxelGlassSectionFooter(
                    speechDetectionString(
                        "settings.speechDetection.launchAtLoginFooter",
                        "Works while Luxel is open. Turn on Launch at Login to make it available "
                            + "after you sign in."
                    ))
            }
            .padding(.leading, 6)
            .padding(.top, 8)
        }
    }

    var speechDetectionPromptsSelection: Binding<Bool> {
        Binding {
            model.settings.speechDetectionPromptsEnabled
        } set: { isEnabled in
            if !isEnabled {
                Task { await model.disableVoiceDetectionPrompts() }
            } else if model.settings.speechDetectionDisclosureAccepted {
                Task { await model.enablePreviouslyDisclosedVoiceDetection() }
            } else {
                isShowingSpeechDetectionDisclosure = true
            }
        }
    }

    var isMicrophoneSelectionEnabled: Bool {
        model.settings.recordAudio || model.settings.speechDetectionPromptsEnabled
    }

    var appNotificationsSelection: Binding<Bool> {
        Binding {
            model.appNotificationSettings.isAuthorized
        } set: { isEnabled in
            Task { await model.setAppNotificationsEnabled(isEnabled) }
        }
    }

    var timeSensitiveNotificationsSelection: Binding<Bool> {
        Binding {
            model.appNotificationSettings.timeSensitiveSetting == .enabled
        } set: { _ in
            Task { await model.openAppNotificationSettings() }
        }
    }

    var notificationPermissionFooter: String {
        if !model.appNotificationSettings.isAuthorized {
            return notificationString(
                "settings.notifications.permissionRequired",
                "Notifications are off in macOS. Turn them on to receive speech prompts."
            )
        }
        if model.appNotificationSettings.timeSensitiveSetting != .enabled {
            return notificationString(
                "settings.notifications.timeSensitiveRequired",
                "Enable Time Sensitive notifications in macOS so speech prompts can bypass summaries and Focus."
            )
        }
        return notificationString(
            "settings.notifications.timeSensitiveActive",
            "Speech prompts are Time Sensitive and can bypass summaries and Focus when macOS allows it."
        )
    }

    func speechDetectionString(_ key: String, _ defaultValue: String) -> String {
        LuxelLocalization.string(key, defaultValue: defaultValue)
    }

    func notificationString(_ key: String, _ defaultValue: String) -> String {
        LuxelLocalization.string(key, defaultValue: defaultValue)
    }
}
