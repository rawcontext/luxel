import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    var speechDetectionSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsIslandGroup(speechDetectionString(
                "settings.speechDetection.title",
                "Speech Detection"
            )) {
                settingsToggleRow(
                    speechDetectionString(
                        "settings.speechDetection.toggle",
                        "Notify When Speech Is Detected"
                    ),
                    isOn: speechDetectionPromptsSelection
                )
                .help(speechDetectionString(
                    "settings.speechDetection.help",
                    "Show a recording prompt after Luxel detects sustained speech on the selected microphone."
                ))

                LuxelGlassRowDivider()

                SettingsRow(speechDetectionString(
                    "settings.speechDetection.status.label",
                    "Status"
                )) {
                    HStack(spacing: 10) {
                        Text(speechDetectionStatusText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.68))

                        speechDetectionRecoveryButton
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(speechDetectionString(
                    "settings.speechDetection.accessibility.label",
                    "Speech detection status"
                ))
                .accessibilityValue(speechDetectionStatusText)
                .accessibilityHint(speechDetectionString(
                    "settings.speechDetection.accessibility.hint",
                    "Shows whether Luxel is listening, paused, or needs attention."
                ))
            }

            VStack(alignment: .leading, spacing: 2) {
                LuxelGlassSectionFooter(speechDetectionString(
                    "settings.speechDetection.footer",
                    "Luxel analyzes microphone audio on this Mac while it is running. "
                        + "Audio is discarded unless you start recording."
                ))
                LuxelGlassSectionFooter(speechDetectionString(
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

    var speechDetectionStatusText: String {
        switch model.voiceDetectionStatus {
        case .off:
            speechDetectionString("settings.speechDetection.status.off", "Off")
        case .preparing:
            speechDetectionString("settings.speechDetection.status.preparing", "Preparing")
        case .listening(let microphoneName):
            LuxelLocalization.format(
                "settings.speechDetection.status.listening",
                defaultValue: "Listening on %@",
                microphoneName
            )
        case .pausedWhileRecording:
            speechDetectionString(
                "settings.speechDetection.status.pausedRecording",
                "Paused while recording"
            )
        case .pausedWhileLocked:
            speechDetectionString(
                "settings.speechDetection.status.pausedLocked",
                "Paused while your Mac is locked"
            )
        case .microphoneAccessRequired:
            speechDetectionString(
                "settings.speechDetection.status.microphoneRequired",
                "Microphone access required"
            )
        case .notificationsRequired:
            speechDetectionString(
                "settings.speechDetection.status.notificationsRequired",
                "Notifications required"
            )
        case .selectedMicrophoneUnavailable:
            speechDetectionString(
                "settings.speechDetection.status.microphoneUnavailable",
                "Selected microphone unavailable"
            )
        case .unavailable:
            speechDetectionString(
                "settings.speechDetection.status.unavailable",
                "Speech detection unavailable"
            )
        }
    }

    @ViewBuilder
    var speechDetectionRecoveryButton: some View {
        switch model.voiceDetectionStatus {
        case .microphoneAccessRequired:
            if model.microphoneStatus == .notDetermined || model.microphoneStatus == .unknown {
                Button(speechDetectionString(
                    "settings.speechDetection.recovery.allowMicrophone",
                    "Allow"
                )) {
                    Task { await model.recoverVoiceDetectionMicrophoneAccess() }
                }
                .buttonStyle(.borderless)
            } else {
                Button(speechDetectionString(
                    "settings.speechDetection.recovery.openMicrophoneSettings",
                    "Open Settings"
                )) {
                    Task { await model.recoverVoiceDetectionMicrophoneAccess() }
                }
                .buttonStyle(.borderless)
            }
        case .notificationsRequired:
            if model.voiceDetectionNotificationStatus == .notDetermined {
                Button(speechDetectionString(
                    "settings.speechDetection.recovery.allowNotifications",
                    "Allow Notifications"
                )) {
                    Task { await model.recoverVoiceDetectionNotificationAccess() }
                }
                .buttonStyle(.borderless)
            } else {
                Button(speechDetectionString(
                    "settings.speechDetection.recovery.notifications",
                    "Notification Settings"
                )) {
                    Task { await model.recoverVoiceDetectionNotificationAccess() }
                }
                .buttonStyle(.borderless)
            }
        default:
            EmptyView()
        }
    }

    func speechDetectionString(_ key: String, _ defaultValue: String) -> String {
        LuxelLocalization.string(key, defaultValue: defaultValue)
    }
}
