import AVFoundation
import LuxelCore
import LuxelPresentation
import SwiftUI

enum KnownSpeakerAccent {
    static let palette: [Color] = [
        Color(red: 0.44, green: 0.85, blue: 0.95),
        Color(red: 0.62, green: 0.58, blue: 1.0),
        Color(red: 0.95, green: 0.77, blue: 0.44),
        Color(red: 0.55, green: 0.9, blue: 0.6),
        Color(red: 0.96, green: 0.56, blue: 0.62)
    ]

    static func accent(at index: Int) -> Color {
        palette[abs(index) % palette.count]
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let initials = words.compactMap(\.first).map(String.init).joined()
        return initials.isEmpty ? "?" : initials.uppercased()
    }
}

@MainActor
final class SettingsClipPlayer {
    static let shared = SettingsClipPlayer()

    private let player = AVPlayer()

    func play(_ url: URL) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}

struct KnownSpeakerSettingsRow: View {
    let profile: KnownSpeakerProfile
    let accent: Color
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onRename: (String) -> Void
    let onRemoveClip: (UUID) -> Void
    let onDelete: () -> Void

    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if isExpanded {
                expandedDetail
            }
        }
        .onChange(of: isExpanded) {
            draftName = profile.displayName
        }
    }

    private var headerRow: some View {
        Button {
            onToggleExpanded()
        } label: {
            HStack(spacing: 11) {
                avatar

                if isExpanded {
                    HStack(spacing: 7) {
                        TextField("Name", text: $draftName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .focused($isNameFocused)
                            .onSubmit {
                                onRename(draftName)
                            }

                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.22))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))

                        Text(collapsedSummary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer(minLength: 8)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(isExpanded ? 0.5 : 0.4))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse speaker" : "Expand speaker to manage clips and name.")
    }

    private var avatar: some View {
        Text(KnownSpeakerAccent.initials(for: profile.displayName))
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: 32, height: 32)
            .background {
                Circle()
                    .fill(accent.opacity(0.16))
                    .overlay {
                        Circle().strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
                    }
            }
    }

    private var collapsedSummary: String {
        var parts: [String] = []
        parts.append(
            profile.exampleClips.count == 1
                ? "1 example clip" : "\(profile.exampleClips.count) example clips")
        parts.append(matchedSummary)
        if let lastHeard = lastHeardText {
            parts.append(lastHeard)
        }

        return parts.joined(separator: " · ")
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !profile.exampleClips.isEmpty {
                HStack(spacing: 6) {
                    Text("EXAMPLE CLIPS")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.trailing, 2)

                    ForEach(profile.exampleClips) { clip in
                        exampleClipChip(clip)
                    }
                }
            }

            HStack {
                Text(expandedSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))

                Spacer()

                Button("Delete Speaker…") {
                    onDelete()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 1, green: 0.54, blue: 0.5))
                .help("Remove this voice profile and its example clips.")
            }
        }
        .padding(.leading, 43)
        .padding(.bottom, 14)
        .padding(.top, 2)
    }

    private func exampleClipChip(_ clip: KnownSpeakerExampleClip) -> some View {
        HStack(spacing: 6) {
            Button {
                SettingsClipPlayer.shared.play(clip.audioURL)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)
            .help("Play this example clip.")

            Text(clipDurationText(clip.duration))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))

            Button {
                onRemoveClip(clip.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .help("Remove this example clip.")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.white.opacity(0.08))
        }
    }

    private var matchedSummary: String {
        profile.matchedRecordingCount == 1
            ? "Matched in 1 recording"
            : "Matched in \(profile.matchedRecordingCount) recordings"
    }

    private var expandedSummary: String {
        var parts = [matchedSummary]
        if let lastHeard = lastHeardText {
            parts.append(lastHeard)
        }
        parts.append("Keep 3–5 short, clear clips")
        return parts.joined(separator: " · ")
    }

    private var lastHeardText: String? {
        guard let lastMatchedAt = profile.lastMatchedAt else {
            return nil
        }

        return "Last heard \(lastMatchedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    private func clipDurationText(_ duration: TimeInterval) -> String {
        let seconds = max(1, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
