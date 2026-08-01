import LuxelCore
import SwiftUI

enum LuxelCaptureMode: CaseIterable {
    case display
    case window
    case area
    case audio

    var title: String {
        switch self {
        case .display:
            "Display"
        case .window:
            "Window"
        case .area:
            "Area"
        case .audio:
            "Audio"
        }
    }

    var systemImage: String {
        switch self {
        case .display:
            "display"
        case .window:
            "macwindow"
        case .area:
            "viewfinder"
        case .audio:
            "waveform"
        }
    }
}

extension LuxelMenu {
    var captureIsland: some View {
        VStack(spacing: 6) {
            captureModeSelector

            VStack(spacing: 9) {
                recordButton
                recordButtonLabel
                captureTargetChip
            }
            .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 16, trailing: 10))
        .luxelMenuIslandBackground(cornerRadius: 30)
    }

    private var captureModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(LuxelCaptureMode.allCases, id: \.self) { mode in
                captureModeSegment(mode)
            }
        }
        .padding(4)
        .background(
            Color.black.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func captureModeSegment(_ mode: LuxelCaptureMode) -> some View {
        let isSelected = captureMode == mode

        return Button {
            selectCaptureMode(mode)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(mode.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.48))
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.16))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.hasActiveRecording)
        .help("\(mode.title) mode")
        .accessibilityLabel("\(mode.title) mode")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    func selectCaptureMode(_ mode: LuxelCaptureMode) {
        guard !model.hasActiveRecording else {
            return
        }

        captureMode = mode

        switch mode {
        case .display:
            alignSelectedCaptureTarget(kind: .display)
        case .window:
            alignSelectedCaptureTarget(kind: .window)
        case .area, .audio:
            break
        }
    }

    private func alignSelectedCaptureTarget(kind: CaptureTargetKind) {
        guard model.selectedCaptureTarget?.kind != kind,
              let target = model.captureTargets.first(where: { $0.kind == kind })
        else {
            return
        }

        model.selectedCaptureTargetID = target.id
        model.syncCameraPreviewSnapArea()
    }

    private var recordButton: some View {
        Button {
            performRecordButtonAction()
        } label: {
            recordButtonRing
        }
        .buttonStyle(LuxelRecordButtonStyle())
        .disabled(!recordButtonIsEnabled)
        .help(recordButtonHelp)
        .accessibilityLabel(recordButtonHelp)
    }

    private var recordButtonRing: some View {
        let isRecording = model.hasActiveRecording
        let innerSize: CGFloat = isRecording ? 30 : 56
        let innerCornerRadius: CGFloat = isRecording ? 8 : innerSize / 2

        return ZStack {
            Circle()
                .fill(Color(red: 16 / 255, green: 16 / 255, blue: 24 / 255).opacity(0.4))

            Circle()
                .strokeBorder(.white.opacity(isRecording ? 1 : 0.92), lineWidth: 3)

            RoundedRectangle(cornerRadius: innerCornerRadius, style: .continuous)
                .fill(recordButtonFill)
                .frame(width: innerSize, height: innerSize)
                .shadow(
                    color: LuxelMenuIslandStyle.recordGlow.opacity(0.5),
                    radius: 9,
                    y: 4
                )
        }
        .frame(width: 72, height: 72)
        .shadow(
            color: LuxelMenuIslandStyle.recordGlow.opacity(isRecording ? 0.5 : 0.18),
            radius: 20
        )
        .contentShape(Circle())
        .animation(.easeInOut(duration: 0.22), value: isRecording)
    }

    private var recordButtonFill: RadialGradient {
        RadialGradient(
            colors: [LuxelMenuIslandStyle.recordRedTop, LuxelMenuIslandStyle.recordRedBottom],
            center: UnitPoint(x: 0.5, y: 0.28),
            startRadius: 0,
            endRadius: 44
        )
    }

    @ViewBuilder
    private var recordButtonLabel: some View {
        if model.hasActiveRecording {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(activeRecordingLabelText(now: context.date))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(activeRecordingLabelColor)
            }
        } else {
            Text(idleRecordLabelText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    private var idleRecordLabelText: String {
        switch captureMode {
        case .display:
            "Record"
        case .window:
            effectiveCaptureTarget(kind: .window) != nil ? "Record" : "Choose a Window"
        case .area:
            "Record Selection"
        case .audio:
            "Record Audio"
        }
    }

    var idleRecordDescription: String {
        switch captureMode {
        case .display:
            if let target = effectiveCaptureTarget(kind: .display) {
                return "Record \(target.title)"
            }

            return "Record Display"
        case .window:
            if let target = effectiveCaptureTarget(kind: .window) {
                return "Record \(target.title)"
            }

            return "Choose a Window"
        case .area:
            return "Record Selection"
        case .audio:
            return "Record Audio"
        }
    }

    private func activeRecordingLabelText(now: Date) -> String {
        switch model.recordingState {
        case .recording(_, let clock), .resuming(_, let clock):
            "Recording \(Self.elapsedText(clock.elapsed(at: now))) · click to stop"
        case .paused(_, let clock), .pausing(_, let clock):
            "Paused \(Self.elapsedText(clock.elapsed(at: now)))"
        case .countingDown:
            "Starting · click to cancel"
        case .stopping:
            "Finishing recording"
        case .idle, .starting, .exporting, .failed:
            ""
        }
    }

    private var activeRecordingLabelColor: Color {
        switch model.recordingState {
        case .recording, .resuming:
            LuxelMenuIslandStyle.recordRedTop.opacity(0.9)
        case .idle, .starting, .countingDown, .pausing, .paused, .stopping, .exporting, .failed:
            .white.opacity(0.85)
        }
    }

    private static func elapsedText(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"

        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours):\(paddedMinutes):\(paddedSeconds)"
        }

        return "\(minutes):\(paddedSeconds)"
    }

    func performRecordButtonAction() {
        if model.hasActiveRecording {
            Task { @MainActor in
                let stopAction = await model.stopRecording()
                if case .openEditor(let fileURL) = stopAction {
                    openRecording(fileURL)
                }
            }
            return
        }

        guard recordButtonCanStart else {
            recoverRecordButtonAction()
            return
        }

        switch captureMode {
        case .display, .window:
            let kind: CaptureTargetKind = captureMode == .display ? .display : .window
            guard let target = effectiveCaptureTarget(kind: kind) else {
                return
            }

            model.selectedCaptureTargetID = target.id
            startAfterDismissingMenu {
                await model.startRecordingFromSelectedTarget()
            }
        case .area:
            startAfterDismissingMenu {
                showAreaCapturePicker()
            }
        case .audio:
            startAfterDismissingMenu {
                await model.startAudioOnlyRecording()
            }
        }
    }

    private func recoverRecordButtonAction() {
        switch captureMode {
        case .display, .window, .area:
            presentPermissionPrompt(.screenPixels)
        case .audio:
            if let source = audioCaptureRecoverySource() {
                presentPermissionPrompt(source)
            }
        }
    }

    func audioCaptureRecoverySource() -> CapturePermissionSource? {
        model.audioCaptureRecoverySource()
    }
}

private struct LuxelRecordButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
