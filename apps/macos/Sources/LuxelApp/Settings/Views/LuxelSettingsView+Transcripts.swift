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

            precisionTranscriptionRow

            LuxelGlassRowDivider()

            transcriptsToggleRow(
                "Segment Transcript Turns",
                isOn: $model.settings.transcriptTurnSegmentationEnabled
            )
            .help("Use Apple Intelligence to group audio transcripts into display turns.")
        }
        .confirmationDialog(
            "Download Precision Transcription?",
            isPresented: $isShowingPrecisionDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("Download and Enable") {
                model.installAndEnablePrecisionTranscription()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                LuxelLocalization.resource(
                    "precision.download.disclosure",
                    defaultValue: """
                        Downloads 483 MB from huggingface.co and needs about 1.05 GB free while installing. \
                        The CC-BY-4.0 Parakeet model supports 25 European languages. \
                        After installation, transcription runs locally and audio is never uploaded.
                        """
                )
            )
        }
        .confirmationDialog(
            "Remove Precision Transcription?",
            isPresented: $isShowingPrecisionRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Model", role: .destructive) {
                model.removePrecisionModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Luxel will switch to Apple Speech. Existing transcript caches are retained.")
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

        SettingsIslandGroup(
            "Local Models",
            footer:
                "Model downloads use normal HTTPS network metadata. Recording audio, transcripts, and projects are never sent."
        ) {
            precisionModelManagementRow
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

    @ViewBuilder
    private var precisionTranscriptionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Precision Transcription", isOn: precisionToggleBinding)
                .toggleStyle(LuxelGlassSwitchToggleStyle())

            Text(precisionTranscriptionDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))

            if case .notInstalled = model.precisionModelState {
                Button("Download and Enable...") {
                    isShowingPrecisionDownloadConfirmation = true
                }
                .disabled(!model.precisionLanguageIsSupported)
            }

            if !model.precisionLanguageIsSupported {
                Text("Choose one of the 25 supported European languages before enabling Precision.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange.opacity(0.85))
            }
        }
        .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    private var precisionToggleBinding: Binding<Bool> {
        Binding {
            model.settings.transcriptEnginePreference == .precision
        } set: { enabled in
            if enabled {
                switch model.precisionModelState {
                case .ready, .updateAvailable:
                    model.setPrecisionTranscriptionEnabled(true)
                default:
                    isShowingPrecisionDownloadConfirmation = true
                }
            } else {
                model.setPrecisionTranscriptionEnabled(false)
            }
        }
    }

    @ViewBuilder
    private var precisionModelManagementRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Parakeet TDT 0.6B v3 (INT8)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(precisionModelStatusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                precisionModelAction
            }

            if let progress = precisionModelProgress {
                ProgressView(value: progress.fractionCompleted)
                Text(
                    "\(byteString(progress.completedBytes)) of \(byteString(progress.totalBytes))"
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            }

            if let error = model.precisionModelErrorMessage {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange.opacity(0.85))
            }

            HStack(spacing: 12) {
                Link(
                    "Model Card",
                    destination: URL(
                        string:
                            "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/aed02740059203c4a87495924f685de3722ae9ce"
                    )!
                )
                Link(
                    "CC-BY-4.0",
                    destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!
                )
            }
            .font(.system(size: 11.5))
        }
        .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
    }

    @ViewBuilder
    private var precisionModelAction: some View {
        switch model.precisionModelState {
        case .notInstalled:
            Button("Download") { isShowingPrecisionDownloadConfirmation = true }
        case .queued, .downloading, .verifying, .preparing, .validating, .canceling:
            Button("Cancel") { model.cancelPrecisionModelInstallation() }
        case .ready, .updateAvailable:
            Button("Remove...") { isShowingPrecisionRemovalConfirmation = true }
        case .repairRequired, .failed:
            Button("Repair") { isShowingPrecisionDownloadConfirmation = true }
        case .removing:
            ProgressView().controlSize(.small)
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

    private var precisionTranscriptionDetail: String {
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
                    defaultValue: "Model installed (%@).",
                    size
                )
        default:
            return LuxelLocalization.string(
                "precision.detail.notInstalled",
                defaultValue: "Higher-accuracy local transcription. Requires a 483 MB download."
            )
        }
    }

    private var precisionModelStatusText: String {
        switch model.precisionModelState {
        case .notInstalled(let downloadBytes, let requiredFreeBytes):
            LuxelLocalization.format(
                "precision.status.notInstalled",
                defaultValue: "Not installed · %@ download · %@ free required",
                byteString(downloadBytes),
                byteString(requiredFreeBytes)
            )
        case .queued(let position):
            LuxelLocalization.format(
                "precision.status.queued",
                defaultValue: "Queued (position %lld)",
                position
            )
        case .downloading:
            LuxelLocalization.string("precision.status.downloading", defaultValue: "Downloading")
        case .verifying:
            LuxelLocalization.string("precision.status.verifying", defaultValue: "Verifying")
        case .preparing:
            LuxelLocalization.string("precision.status.preparing", defaultValue: "Preparing")
        case .validating:
            LuxelLocalization.string(
                "precision.status.validating",
                defaultValue: "Validating offline load"
            )
        case .ready(let installation):
            LuxelLocalization.format(
                "precision.status.ready",
                defaultValue: "Ready · revision %@ · %@",
                String(installation.commit.prefix(7)),
                byteString(installation.allocatedBytes)
            )
        case .updateAvailable:
            LuxelLocalization.string(
                "precision.status.updateAvailable",
                defaultValue: "Update available"
            )
        case .repairRequired:
            LuxelLocalization.string(
                "precision.status.repairRequired",
                defaultValue: "Repair required"
            )
        case .canceling:
            LuxelLocalization.string("precision.status.canceling", defaultValue: "Canceling")
        case .removing:
            LuxelLocalization.string("precision.status.removing", defaultValue: "Removing")
        case .failed:
            LuxelLocalization.string("precision.status.failed", defaultValue: "Setup failed")
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
                                accent: KnownSpeakerAccent.accent(at: index),
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
