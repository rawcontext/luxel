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
            }

            VStack(alignment: .leading, spacing: 2) {
                LuxelGlassSectionFooter(
                    speechDetectionString(
                        "settings.speechDetection.footer",
                        "Luxel analyzes microphone audio on this Mac while it is running. "
                            + "Audio is discarded unless you start recording."
                    ))
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

    func speechDetectionString(_ key: String, _ defaultValue: String) -> String {
        LuxelLocalization.string(key, defaultValue: defaultValue)
    }
}
