import LuxelCore
import SwiftUI

struct LuxelReplayBufferControls: View {
    private static let durationOptions: [TimeInterval] = [30, 60, 120, 300]
    private static let actionButtonHeight: CGFloat = 32
    private static let actionButtonCornerRadius: CGFloat = 16
    private static let durationPickerWidth: CGFloat = 102
    private static let exportButtonWidth: CGFloat = 76
    private static let powerButtonWidth: CGFloat = 74

    let model: LuxelMenuModel
    let openRecording: @MainActor @Sendable (URL) -> Void

    var body: some View {
        let presentation = model.replayBufferMenuPresentation

        Divider()

        VStack(alignment: .leading, spacing: 8) {
            Text("Replay Buffer")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            HStack(spacing: 6) {
                Picker("Duration", selection: replayBufferDurationSelection) {
                    ForEach(Self.durationOptions, id: \.self) { seconds in
                        Text(replayBufferDurationLabel(seconds)).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: Self.durationPickerWidth)
                .disabled(model.replayBufferState == .clipping)
                .help("Choose how much recent recording history to keep.")

                Spacer(minLength: 0)

                exportBufferButton(presentation)

                replayBufferPowerButton
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxelMenuSectionBackground(cornerRadius: 18)
    }

    private var isReplayBufferConfigured: Bool {
        model.settings.replayBufferConfiguration != nil
    }

    private var replayBufferCanStart: Bool {
        guard isReplayBufferConfigured else {
            return true
        }

        return switch model.replayBufferState {
        case .disarmed, .paused(.user):
            true
        case .starting, .buffering, .paused, .clipping:
            false
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

    private var replayBufferPowerButton: some View {
        Button {
            performReplayBufferPowerAction()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: replayBufferPowerSystemImage)
                    .font(.system(size: 11, weight: .semibold))

                Text(replayBufferPowerTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: Self.powerButtonWidth, height: Self.actionButtonHeight)
            .contentShape(
                RoundedRectangle(cornerRadius: Self.actionButtonCornerRadius, style: .continuous))
        }
        .buttonStyle(LuxelMenuControlButtonStyle(cornerRadius: Self.actionButtonCornerRadius))
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
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white)
                .frame(width: Self.exportButtonWidth, height: Self.actionButtonHeight)
        }
        .buttonStyle(LuxelMenuControlButtonStyle(cornerRadius: Self.actionButtonCornerRadius))
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
