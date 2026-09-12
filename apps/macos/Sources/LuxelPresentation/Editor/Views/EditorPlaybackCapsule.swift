import AVFoundation
import LuxelCore
import SwiftUI

enum EditorStageChromeStyle {
    static let navigationFill = Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255)
    static let capsuleFill = Color(red: 20 / 255, green: 20 / 255, blue: 30 / 255).opacity(0.6)
}

struct EditorPlaybackCapsule: View {
    @Bindable var model: LuxelEditorModel
    @State private var volume: Double = 1
    @AppStorage(TranscriptPlaybackPreferences.autoPlayDefaultsKey)
    private var isTranscriptAutoPlayEnabled = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                volumeControls
                    .frame(width: 110, alignment: .leading)

                Spacer(minLength: 12)

                transportControls

                Spacer(minLength: 12)

                autoPlayControls
                    .frame(width: 110, alignment: .trailing)
            }

            scrubberRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(EditorStageChromeStyle.capsuleFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.14), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        }
        .onAppear {
            volume = Double(model.player.volume)
        }
    }

    @ViewBuilder
    private var autoPlayControls: some View {
        if model.visibleTranscript != nil {
            Toggle("Auto-play", isOn: $isTranscriptAutoPlayEnabled)
                .toggleStyle(LuxelGlassCheckboxToggleStyle())
                .fixedSize()
                .help("Automatically start playback when selecting a transcript word.")
        } else {
            Color.clear
                .frame(height: 1)
        }
    }

    private var volumeControls: some View {
        HStack(spacing: 8) {
            Image(systemName: volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))

            Slider(value: volumeSelection, in: 0...1)
                .controlSize(.mini)
                .tint(.white)
                .help("Preview volume")
        }
        .accessibilityLabel("Preview volume")
    }

    private var transportControls: some View {
        HStack(spacing: 14) {
            transportButton(
                systemImage: "backward.end.fill",
                accessibilityLabel: "Go to start",
                help: "Jump to the trimmed start."
            ) {
                model.scrub(to: model.trimStart)
            }

            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.playbackRequested ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(LuxelGlassTheme.prominentText)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 7, y: 2)
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                model.playbackRequested ? LuxelLocalization.string("Pause") : LuxelLocalization.string("Play")
            )
            .help("Play or pause the preview.")

            transportButton(
                systemImage: "forward.end.fill",
                accessibilityLabel: "Go to end",
                help: "Jump to the trimmed end."
            ) {
                model.scrub(to: model.trimEnd)
            }
        }
    }

    private func transportButton(
        systemImage: String,
        accessibilityLabel: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LuxelLocalization.string(accessibilityLabel))
        .help(LocalizedStringKey(help))
    }

    private var scrubberRow: some View {
        HStack(spacing: 10) {
            timeText(model.formatTime(model.currentPlaybackTime))

            Slider(value: playbackTimeSelection, in: 0...max(model.duration, 0.01))
                .controlSize(.small)
                .tint(.white)
                .help("Scrub the preview.")

            timeText(model.formatTime(model.duration))
        }
    }

    private func timeText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
    }

    private var volumeSelection: Binding<Double> {
        Binding {
            volume
        } set: { value in
            volume = value
            model.player.volume = Float(value)
        }
    }

    private var playbackTimeSelection: Binding<Double> {
        Binding {
            model.currentPlaybackTime
        } set: { value in
            model.scrub(to: value)
        }
    }
}
