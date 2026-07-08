import LuxelCore
import SwiftUI

struct LuxelReplayBufferControls: View {
    private static let durationOptions: [TimeInterval] = [30, 60, 120, 300]
    private static let actionButtonHeight: CGFloat = 32
    private static let actionButtonCornerRadius: CGFloat = 16

    let model: LuxelMenuModel
    let openRecording: @MainActor @Sendable (URL) -> Void

    @ViewBuilder
    var body: some View {
        let presentation = model.replayBufferMenuPresentation

        if presentation.isVisible || model.settings.alwaysShowReplayBufferIsland {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Replay Buffer")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.96))
                        .lineLimit(1)

                    durationMenu
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                exportBufferButton(presentation)

                replayBufferPowerButton
            }
            .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 12))
            .luxelMenuIslandBackground(cornerRadius: 24)
        }
    }

    private var durationMenu: some View {
        Menu {
            Picker("Duration", selection: replayBufferDurationSelection) {
                ForEach(Self.durationOptions, id: \.self) { seconds in
                    Text(replayBufferDurationLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(replayBufferDurationSubtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.replayBufferState == .clipping)
        .help("Choose how much recent recording history to keep.")
        .accessibilityLabel("Replay buffer duration")
        .accessibilityValue(replayBufferDurationSubtitle)
    }

    private var isReplayBufferConfigured: Bool {
        model.settings.replayBufferConfiguration != nil
    }

    private var replayBufferCanStart: Bool {
        guard isReplayBufferConfigured else {
            return true
        }

        switch model.replayBufferState {
        case .disarmed, .paused(.user):
            return true
        case .starting, .buffering, .paused, .clipping:
            return false
        }
    }

    private var replayBufferPowerTitle: String {
        replayBufferCanStart ? "Start" : "Stop"
    }

    private var replayBufferPowerSystemImage: String {
        replayBufferCanStart ? "play.fill" : "stop.fill"
    }

    private var replayBufferPowerButtonIsDisabled: Bool {
        switch model.replayBufferState {
        case .starting, .clipping:
            true
        case .disarmed, .buffering, .paused:
            false
        }
    }

    private var replayBufferDurationSelection: Binding<TimeInterval> {
        Binding {
            model.settings.replayBufferConfiguration?.bufferLength
                ?? model.settings.replayBufferPreferredBufferLength
        } set: { duration in
            model.setReplayBufferDuration(duration)
        }
    }

    private var replayBufferDurationSubtitle: String {
        let seconds =
            model.settings.replayBufferConfiguration?.bufferLength
            ?? model.settings.replayBufferPreferredBufferLength

        return "Keeps the last \(replayBufferDurationLabel(seconds).lowercased())"
    }

    private var replayBufferPowerButton: some View {
        Button {
            performReplayBufferPowerAction()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: replayBufferPowerSystemImage)
                    .font(.system(size: 11, weight: .semibold))

                Text(replayBufferPowerTitle)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(red: 22 / 255, green: 22 / 255, blue: 29 / 255))
            .padding(.leading, 11)
            .padding(.trailing, 14)
            .frame(height: Self.actionButtonHeight)
            .contentShape(
                RoundedRectangle(cornerRadius: Self.actionButtonCornerRadius, style: .continuous))
        }
        .buttonStyle(
            LuxelReplayBufferPowerButtonStyle(cornerRadius: Self.actionButtonCornerRadius)
        )
        .disabled(replayBufferPowerButtonIsDisabled)
        .help(replayBufferPowerTitle)
        .accessibilityLabel(replayBufferPowerTitle)
    }

    private func exportBufferButton(_ presentation: ReplayBufferMenuPresentation) -> some View {
        Button {
            Task {
                await model.clipReplayBufferFromMenu(openRecording: openRecording)
            }
        } label: {
            Text("Export")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(presentation.canClip ? 0.9 : 0.35))
                .padding(.horizontal, 13)
                .frame(height: Self.actionButtonHeight)
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(
            LuxelIslandButtonStyle(cornerRadius: 15, fillOpacity: 0.06, dimsWhenDisabled: false)
        )
        .disabled(!presentation.canClip)
        .help(presentation.clipActionTitle)
        .accessibilityLabel("Export")
    }

    private func performReplayBufferPowerAction() {
        guard replayBufferCanStart else {
            Task {
                await model.stopReplayBufferFromMenu(openRecording: openRecording)
            }
            return
        }

        if case .paused(.user) = model.replayBufferState {
            Task {
                await model.toggleReplayBufferPause()
            }
        } else {
            model.setReplayBufferEnabled(true)
        }
    }

    private func replayBufferDurationLabel(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case 30:
            "30 Seconds"
        case 60:
            "1 Minute"
        case 120:
            "2 Minutes"
        case 300:
            "5 Minutes"
        default:
            "\(Int(seconds)) Seconds"
        }
    }
}

private struct LuxelReplayBufferPowerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        LuxelReplayBufferPowerButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isEnabled: isEnabled,
            cornerRadius: cornerRadius
        )
    }
}

private struct LuxelReplayBufferPowerButtonBody<Label: View>: View {
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isEnabled: Bool
    let cornerRadius: CGFloat

    var body: some View {
        label
            .background(
                .white.opacity(isEnabled ? 0.92 : 0.35),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .shadow(
                color: .black.opacity(isHovered ? 0.35 : 0.25),
                radius: isHovered ? 10 : 7,
                y: isHovered ? 4 : 2
            )
            .offset(y: isHovered && !isPressed ? -1 : 0)
            .scaleEffect(isPressed ? 0.95 : 1)
            .onHover { isHovered = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}
