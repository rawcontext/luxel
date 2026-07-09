import LuxelCore
import SwiftUI

/// Display-only speaker accent colors, assigned by first-seen order within a
/// transcript. Never persisted as semantic data.
public enum TranscriptSpeakerPalette {
    public static let dotColors: [Color] = [
        Color(red: 0.62, green: 0.58, blue: 1.0),
        Color(red: 0.44, green: 0.85, blue: 0.95),
        Color(red: 0.95, green: 0.77, blue: 0.44),
        Color(red: 0.55, green: 0.9, blue: 0.6),
        Color(red: 0.96, green: 0.56, blue: 0.62)
    ]

    public static let textColors: [Color] = [
        Color(red: 0.73, green: 0.7, blue: 1.0),
        Color(red: 0.6, green: 0.89, blue: 0.96),
        Color(red: 0.96, green: 0.84, blue: 0.6),
        Color(red: 0.68, green: 0.93, blue: 0.72),
        Color(red: 0.97, green: 0.68, blue: 0.73)
    ]

    public static func dotColor(at index: Int) -> Color {
        dotColors[abs(index) % dotColors.count]
    }

    public static func textColor(at index: Int) -> Color {
        textColors[abs(index) % textColors.count]
    }
}

struct EditorSpeakersCard: View {
    @Bindable var model: LuxelEditorModel
    @State private var expandedVoiceID: String?
    @State private var nameDrafts: [String: String] = [:]

    var body: some View {
        EditorDisclosureCard("Speakers") {
            VStack(alignment: .leading, spacing: 10) {
                speakerDetectionControls

                if !model.visibleSpeakerVoices.isEmpty {
                    LuxelGlassRowDivider()
                }

                ForEach(model.visibleSpeakerVoices) { voice in
                    if voice.label.knownSpeakerID != nil {
                        matchedVoiceRow(voice)
                    } else if isExpanded(voice) {
                        expandedAnonymousVoiceCard(voice)
                    } else {
                        collapsedAnonymousVoiceRow(voice)
                    }
                }
            }
        }
        .onAppear {
            expandFirstAnonymousVoiceIfNeeded()
        }
        .onChange(of: model.visibleSpeakerVoices.map(\.id)) {
            expandFirstAnonymousVoiceIfNeeded()
        }
    }

    private func isExpanded(_ voice: DetectedSpeakerVoice) -> Bool {
        expandedVoiceID == voice.id
    }

    private func expandFirstAnonymousVoiceIfNeeded() {
        let anonymousVoices = model.visibleSpeakerVoices.filter {
            $0.label.knownSpeakerID == nil
        }
        if let expandedVoiceID, anonymousVoices.contains(where: { $0.id == expandedVoiceID }) {
            return
        }

        expandedVoiceID = anonymousVoices.first?.id
    }

    // MARK: - Detection

    private var speakerDetectionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Detection")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer(minLength: 8)

                Button {
                    model.applySpeakerCountHint()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.75))
                .disabled(!model.canApplySpeakerCountHint)
                .opacity(model.canApplySpeakerCountHint ? 1 : 0.35)
                .help("Re-run speaker detection with these settings.")
            }

            Picker(
                "Detection",
                selection: Binding(
                    get: { model.speakerCountMode },
                    set: { model.setSpeakerCountMode($0) }
                )
            ) {
                ForEach(EditorSpeakerCountMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)

            switch model.speakerCountMode {
            case .automatic:
                EmptyView()
            case .exact:
                exactSpeakerCountControl
            case .range:
                speakerCountRangeControls
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    private var exactSpeakerCountControl: some View {
        Stepper(
            value: Binding(
                get: { model.exactSpeakerCount },
                set: { model.setExactSpeakerCount($0) }
            ),
            in: 1...12
        ) {
            Text(speakerCountLabel(model.exactSpeakerCount))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .controlSize(.small)
        .help("Set the expected number of speakers.")
    }

    private var speakerCountRangeControls: some View {
        HStack(spacing: 10) {
            Stepper(
                value: Binding(
                    get: { model.minimumSpeakerCount },
                    set: { model.setMinimumSpeakerCount($0) }
                ),
                in: 1...12
            ) {
                Text("Min \(model.minimumSpeakerCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(minWidth: 42, alignment: .leading)
            }
            .controlSize(.small)
            .help("Set the minimum expected speaker count.")

            Stepper(
                value: Binding(
                    get: { model.maximumSpeakerCount },
                    set: { model.setMaximumSpeakerCount($0) }
                ),
                in: 1...12
            ) {
                Text("Max \(model.maximumSpeakerCount)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(minWidth: 42, alignment: .leading)
            }
            .controlSize(.small)
            .help("Set the maximum expected speaker count.")
        }
    }

    // MARK: - Rows

    private func voiceHeader(_ voice: DetectedSpeakerVoice, showsMatchCheck: Bool = false)
    -> some View {
        HStack(spacing: 8) {
            speakerDot(voice)

            Text(voice.label.displayName)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)

            if showsMatchCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(red: 0.5, green: 0.91, blue: 0.61))
            }

            Spacer(minLength: 8)

            Text(voiceStats(voice))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private func speakerDot(_ voice: DetectedSpeakerVoice) -> some View {
        let color = TranscriptSpeakerPalette.dotColor(
            at: model.speakerAccentIndex(for: voice.id) ?? 0)
        return Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color.opacity(0.5), radius: 4)
    }

    private func matchedVoiceRow(_ voice: DetectedSpeakerVoice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            voiceHeader(voice, showsMatchCheck: true)

            HStack(spacing: 6) {
                Text("Matched from Known Speakers")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))

                Button("Reset") {
                    model.resetDetectedVoiceMatch(speakerID: voice.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .help("Return this voice to an anonymous speaker label.")
            }
            .padding(.leading, 17)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
    }

    private func collapsedAnonymousVoiceRow(_ voice: DetectedSpeakerVoice) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                expandedVoiceID = voice.id
            }
        } label: {
            HStack(spacing: 8) {
                voiceHeader(voice)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Expand to name or save this voice.")
    }

    private func expandedAnonymousVoiceCard(_ voice: DetectedSpeakerVoice) -> some View {
        let draftName = nameDrafts[voice.id] ?? ""
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 9) {
            voiceHeader(voice)

            if !voice.exampleRanges.isEmpty {
                exampleRangesRow(voice)
            }

            nameField(for: voice)

            saveButton(for: voice, trimmedName: trimmedName)

            attachAndIgnoreRow(for: voice)
        }
        .padding(11)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                }
        }
    }

    private func exampleRangesRow(_ voice: DetectedSpeakerVoice) -> some View {
        HStack(spacing: 5) {
            ForEach(voice.exampleRanges, id: \.self) { range in
                exampleRangeChip(range)
            }

            Text("examples")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.leading, 2)
        }
    }

    private func nameField(for voice: DetectedSpeakerVoice) -> some View {
        TextField(
            "Add name…",
            text: Binding(
                get: { nameDrafts[voice.id] ?? "" },
                set: { nameDrafts[voice.id] = $0 }
            )
        )
        .textFieldStyle(.plain)
        .font(.system(size: 11.5))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black.opacity(0.22))
        }
    }

    private func saveButton(for voice: DetectedSpeakerVoice, trimmedName: String) -> some View {
        Button {
            model.saveDetectedVoiceAsKnownSpeaker(speakerID: voice.id, name: trimmedName)
        } label: {
            Text("Save as Known Speaker")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color(red: 0.09, green: 0.09, blue: 0.11))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.92))
                }
        }
        .buttonStyle(.plain)
        .disabled(trimmedName.isEmpty || !voice.hasEmbedding)
        .opacity(trimmedName.isEmpty || !voice.hasEmbedding ? 0.45 : 1)
        .help(
            voice.hasEmbedding
                ? "Save this voice with the entered name for future recordings."
                : "This voice has no usable voice signature to save."
        )
    }

    private func attachAndIgnoreRow(for voice: DetectedSpeakerVoice) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(model.knownSpeakerOptions) { profile in
                    Button(profile.displayName) {
                        model.attachDetectedVoice(
                            speakerID: voice.id,
                            toKnownSpeakerWithID: profile.id
                        )
                    }
                }
            } label: {
                Text("Attach to Existing…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.white.opacity(0.08))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .disabled(model.knownSpeakerOptions.isEmpty || !voice.hasEmbedding)
            .opacity(model.knownSpeakerOptions.isEmpty || !voice.hasEmbedding ? 0.45 : 1)
            .help("Add this voice to a speaker you already saved.")

            Button("Ignore") {
                model.ignoreDetectedVoice(speakerID: voice.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 10)
            .help("Hide this voice for this recording.")
        }
    }

    private func exampleRangeChip(_ range: SpeakerVoiceExampleRange) -> some View {
        Button {
            model.playSpeakerExample(range)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 7))

                Text(formatDuration(range.duration))
                    .font(.system(size: 10, design: .monospaced))
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.white.opacity(0.08))
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Play an example of this voice.")
    }

    private func voiceStats(_ voice: DetectedSpeakerVoice) -> String {
        let turns = voice.turnCount == 1 ? "1 turn" : "\(voice.turnCount) turns"
        return "\(formatDuration(voice.totalSpeakingTime)) · \(turns)"
    }

    private func speakerCountLabel(_ count: Int) -> String {
        count == 1 ? "1 speaker" : "\(count) speakers"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
