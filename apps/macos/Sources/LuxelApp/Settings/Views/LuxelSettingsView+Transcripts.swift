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
        .confirmationDialog(
            "Switch to Apple Speech?",
            isPresented: unsupportedLanguageConfirmationBinding,
            titleVisibility: .visible
        ) {
            Button("Switch and Change Language") {
                let identifier = pendingUnsupportedPrecisionLanguage
                pendingUnsupportedPrecisionLanguage = nil
                model.applyTranscriptLanguage(
                    identifier?.isEmpty == true ? nil : identifier,
                    switchingToApple: true
                )
            }
            Button("Cancel", role: .cancel) {
                pendingUnsupportedPrecisionLanguage = nil
            }
        } message: {
            Text("Precision Transcription does not support this language. Apple Speech can still use it.")
        }
        .task {
            model.refreshKnownSpeakers()
        }

        precisionTranscriptionCard

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
        Toggle(title, isOn: isOn)
            .toggleStyle(LuxelGlassSwitchToggleStyle())
            .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    private func transcriptLanguageLabel(_ identifier: String?) -> String {
        guard let identifier else {
            return "System Default"
        }

        return Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }

    private var transcriptLanguageBinding: Binding<String?> {
        Binding {
            model.settings.transcriptLanguageIdentifier
        } set: { identifier in
            let locale = identifier.map(Locale.init(identifier:)) ?? .current
            let supported =
                (try? PrecisionTranscriptionLanguageCatalog.languageCode(for: locale)) != nil
            if model.settings.transcriptEnginePreference == .precision, !supported {
                pendingUnsupportedPrecisionLanguage = identifier ?? ""
            } else {
                model.applyTranscriptLanguage(identifier)
            }
        }
    }

    private var unsupportedLanguageConfirmationBinding: Binding<Bool> {
        Binding {
            pendingUnsupportedPrecisionLanguage != nil
        } set: { isPresented in
            if !isPresented {
                pendingUnsupportedPrecisionLanguage = nil
            }
        }
    }

    private var precisionTranscriptionCard: some View {
        SettingsIslandGroup(
            "Precision Transcription",
            footer: LuxelLocalization.string(
                "precision.detail.notInstalled",
                defaultValue: "Higher-accuracy local transcription. Requires a 483 MB download."
            )
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            LuxelLocalization.string(
                                "precision.marketing.description",
                                defaultValue:
                                    "More accurate words and timing, processed entirely on your Mac."
                            )
                        )
                        .font(.system(size: 13, weight: .medium))

                        if let status = precisionFeatureStatusText {
                            Text(status)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }

                    Spacer(minLength: 16)

                    Toggle("Precision Transcription", isOn: precisionToggleBinding)
                        .toggleStyle(LuxelGlassSwitchToggleStyle(showsLabel: false))
                        .disabled(precisionToggleIsLocked)
                        .accessibilityLabel("Precision Transcription")
                }

                if let progress = precisionModelProgress {
                    ProgressView(value: progress.fractionCompleted)
                    Text(
                        "\(progressByteString(progress.completedBytes)) of \(progressByteString(progress.totalBytes))"
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                }

                if !model.precisionLanguageIsSupported {
                    Text("Choose one of the 25 supported European languages before enabling Precision.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange.opacity(0.85))
                }

                if let error = model.precisionModelErrorMessage {
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange.opacity(0.85))
                }
            }
            .padding(.vertical, 9)
        }
    }

    private var precisionToggleBinding: Binding<Bool> {
        Binding {
            precisionToggleIsOn
        } set: { enabled in
            if enabled {
                switch model.precisionModelState {
                case .ready, .updateAvailable:
                    model.setPrecisionTranscriptionEnabled(true)
                default:
                    model.installAndEnablePrecisionTranscription()
                }
            } else {
                switch model.precisionModelState {
                case .queued, .downloading, .verifying, .preparing, .validating:
                    model.cancelPrecisionModelInstallation()
                case .ready, .updateAvailable:
                    model.removePrecisionModel()
                default:
                    model.setPrecisionTranscriptionEnabled(false)
                }
            }
        }
    }

    private var precisionToggleIsOn: Bool {
        if model.settings.transcriptEnginePreference == .precision {
            return true
        }

        return switch model.precisionModelState {
        case .queued, .downloading, .verifying, .preparing, .validating:
            true
        default:
            false
        }
    }

    private var precisionToggleIsLocked: Bool {
        return switch model.precisionModelState {
        case .canceling, .removing:
            true
        default:
            !model.precisionLanguageIsSupported && !precisionToggleIsOn
        }
    }

    private var precisionModelProgress: LocalModelProgress? {
        switch model.precisionModelState {
        case .downloading(let progress), .verifying(let progress):
            progress
        case .preparing(let progress):
            progress
        default:
            nil
        }
    }

    private var precisionFeatureStatusText: String? {
        switch model.precisionModelState {
        case .ready(let installation), .updateAvailable(let installation, _):
            let size = byteString(installation.allocatedBytes)
            return model.settings.transcriptEnginePreference == .precision
                ? LuxelLocalization.format(
                    "precision.detail.enabled",
                    defaultValue: "Runs locally. Uses %@ on disk.",
                    size
                )
                : LuxelLocalization.format(
                    "precision.detail.installed",
                    defaultValue: "Downloaded and ready (%@).",
                    size
                )
        case .notInstalled:
            return nil
        case .queued(let position):
            return LuxelLocalization.format(
                "precision.status.queued",
                defaultValue: "Queued (position %lld)",
                position
            )
        case .downloading:
            return LuxelLocalization.string(
                "precision.status.downloading",
                defaultValue: "Downloading"
            )
        case .verifying:
            return LuxelLocalization.string(
                "precision.status.verifying",
                defaultValue: "Verifying"
            )
        case .preparing:
            return LuxelLocalization.string(
                "precision.status.preparing",
                defaultValue: "Preparing"
            )
        case .validating:
            return LuxelLocalization.string(
                "precision.status.validating",
                defaultValue: "Validating offline load"
            )
        case .repairRequired:
            return LuxelLocalization.string(
                "precision.status.repairRequired",
                defaultValue: "Repair required"
            )
        case .canceling:
            return LuxelLocalization.string(
                "precision.status.canceling",
                defaultValue: "Canceling"
            )
        case .removing:
            return LuxelLocalization.string(
                "precision.status.removing",
                defaultValue: "Removing"
            )
        case .failed:
            return LuxelLocalization.string(
                "precision.status.failed",
                defaultValue: "Setup failed"
            )
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func progressByteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.zeroPadsFractionDigits = true
        return formatter.string(fromByteCount: bytes)
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
        model.knownSpeakers.count == 1 ? "1 saved" : "\(model.knownSpeakers.count) saved"
    }
}
