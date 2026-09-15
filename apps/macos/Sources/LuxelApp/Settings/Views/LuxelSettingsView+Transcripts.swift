import AVFoundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    private static let knownSpeakersPrivacyFooter =
        "Voice profiles are stored locally and never synced or uploaded. "
        + "Save new speakers from a recording's Speakers list."

    private static let transcriptLanguageOptions: [String?] = [
        nil,
        "bg", "cs", "da", "de-DE", "el", "en-US", "en-GB", "es-ES", "et", "fi",
        "fr-FR", "hr", "hu", "it-IT", "lt", "lv", "mt", "nl", "pl", "pt-BR",
        "ro", "ru", "sk", "sl", "sv", "uk",
        "ja-JP", "ko-KR", "zh-CN"
    ]

    @ViewBuilder
    var transcriptsSettingsForm: some View {
        recordingNamesSettingsGroup
        SettingsIslandGroup(
            "Transcription",
            footer:
                "Transcripts are generated on this Mac. Turn segmentation groups text by natural pauses."
        ) {
            SettingsRow("Transcript Language") {
                SettingsMenuPicker(
                    selection: transcriptLanguageBinding,
                    options: Self.transcriptLanguageOptions
                ) { identifier in
                    transcriptLanguageLabel(identifier)
                }
            }
            .help("Choose the language used for new transcripts.")

            LuxelGlassRowDivider()

            transcriptsToggleRow(
                "Segment Transcript Turns",
                isOn: $model.settings.transcriptTurnSegmentationEnabled
            )
            .help("Use Apple Intelligence to group audio transcripts into display turns.")
        }
        .task {
            model.refreshKnownSpeakers()
        }

        SettingsIslandGroup(
            "Speakers",
            footer:
                "Labels transcript turns by speaker using a local model. Audio and voice profiles never leave your Mac."
        ) {
            transcriptsToggleRow("Identify Speakers", isOn: identifySpeakersBinding)
                .help("Label transcript turns by speaker.")
        }

        knownSpeakersGroup
    }

    private func transcriptsToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(LocalizedStringKey(title), isOn: isOn)
            .toggleStyle(LuxelGlassSwitchToggleStyle())
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    private func transcriptLanguageLabel(_ identifier: String?) -> String {
        guard let identifier else {
            return LuxelLocalization.string("System Default")
        }

        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private var transcriptLanguageBinding: Binding<String?> {
        Binding {
            model.settings.transcriptLanguageIdentifier
        } set: { identifier in
            model.applyTranscriptLanguage(identifier)
        }
    }

    private var identifySpeakersBinding: Binding<Bool> {
        Binding {
            model.settings.transcriptSpeakerDiarizationEnabled
        } set: { isEnabled in
            model.setSpeakerDiarizationEnabled(isEnabled)
        }
    }

    // MARK: - Known speakers

    @ViewBuilder
    private var knownSpeakersGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                LuxelGlassSectionHeader("Known Speakers")

                Spacer()

                Text(knownSpeakersCountText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 10)

            LuxelGlassIsland(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    if model.knownSpeakers.isEmpty {
                        Text("No saved speakers yet.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
                    } else {
                        ForEach(
                            Array(model.knownSpeakers.enumerated()), id: \.element.id
                        ) { index, profile in
                            if index > 0 {
                                LuxelGlassRowDivider()
                            }

                            KnownSpeakerSettingsRow(
                                profile: profile,
                                isExpanded: model.expandedKnownSpeakerID == profile.id,
                                onToggleExpanded: {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        model.expandedKnownSpeakerID =
                                            model.expandedKnownSpeakerID == profile.id
                                            ? nil : profile.id
                                    }
                                },
                                onRename: { name in
                                    model.renameKnownSpeaker(id: profile.id, to: name)
                                },
                                onRemoveClip: { clipID in
                                    model.removeKnownSpeakerClip(
                                        profileID: profile.id, clipID: clipID)
                                },
                                onDelete: {
                                    model.deleteKnownSpeaker(id: profile.id)
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))

                Text(Self.knownSpeakersPrivacyFooter)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.leading, 6)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var knownSpeakersCountText: String {
        model.knownSpeakers.count == 1
            ? LuxelLocalization.string("1 saved") : LuxelLocalization.format("%d saved", model.knownSpeakers.count)
    }
}
