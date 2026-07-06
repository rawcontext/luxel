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

    private var idleRecordDescription: String {
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

    @ViewBuilder
    private var captureTargetChip: some View {
        switch captureMode {
        case .display:
            captureTargetChipMenu(kind: .display, emptyTitle: "No display found")
        case .window:
            captureTargetChipMenu(kind: .window, emptyTitle: "No windows found")
        case .area:
            captureTargetChipLabel(areaTargetChipText, showsChevron: false)
        case .audio:
            captureTargetChipLabel(audioTargetChipText, showsChevron: false)
        }
    }

    private func captureTargetChipMenu(
        kind: CaptureTargetKind,
        emptyTitle: String
    ) -> some View {
        let targets = model.captureTargets.filter { $0.kind == kind }
        let target = effectiveCaptureTarget(kind: kind)

        return Menu {
            ForEach(targets) { menuTarget in
                Toggle(isOn: captureTargetSelection(menuTarget)) {
                    CaptureTargetMenuLabel(target: menuTarget)
                }
            }
        } label: {
            captureTargetChipLabel(
                target?.title ?? emptyTitle,
                showsChevron: true,
                target: target
            )
        }
        .buttonStyle(.plain)
        .disabled(targets.isEmpty || model.hasActiveRecording)
        .help("Choose \(kind == .display ? "display" : "window")")
    }

    private func captureTargetChipLabel(
        _ title: String,
        showsChevron: Bool,
        target: CaptureTargetOption? = nil
    ) -> some View {
        HStack(spacing: 6) {
            if let target {
                CaptureTargetMenuIcon(target: target, size: 14)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(0.55)
            }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.leading, target == nil ? 12 : 9)
        .padding(.trailing, showsChevron ? 10 : 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 220)
        .background(.white.opacity(0.08), in: Capsule())
        .contentShape(Capsule())
    }

    private var areaTargetChipText: String {
        if let memory = model.settings.lastCaptureMemory,
           case .area = memory.target {
            return "\(memory.pixelSize.width) × \(memory.pixelSize.height) · reselect at record"
        }

        return "Choose area at record"
    }

    private var audioTargetChipText: String {
        let capturesSystemAudio = model.settings.recordSystemAudio
        let capturesMicrophone = model.settings.recordAudio

        if capturesSystemAudio, capturesMicrophone {
            return "System Audio + Mic"
        }

        if capturesSystemAudio {
            return "System Audio"
        }

        if capturesMicrophone {
            return "Microphone"
        }

        return "No audio input on"
    }

    private func captureTargetSelection(_ target: CaptureTargetOption) -> Binding<Bool> {
        Binding {
            target.id == model.selectedCaptureTargetID
        } set: { isSelected in
            guard isSelected else {
                return
            }

            model.selectedCaptureTargetID = target.id
            model.syncCameraPreviewSnapArea()
        }
    }

    private func effectiveCaptureTarget(kind: CaptureTargetKind) -> CaptureTargetOption? {
        if let selected = model.selectedCaptureTarget, selected.kind == kind {
            return selected
        }

        return model.captureTargets.first { $0.kind == kind }
    }

    private var recordButtonIsEnabled: Bool {
        guard !model.hasActiveRecording else {
            switch model.recordingState {
            case .countingDown, .recording, .paused:
                return true
            case .idle, .starting, .pausing, .resuming, .stopping, .exporting, .failed:
                return false
            }
        }

        return recordButtonCanStart || recordButtonCanRecover
    }

    private var recordButtonCanStart: Bool {
        switch captureMode {
        case .display:
            model.canUseRecordButton && effectiveCaptureTarget(kind: .display) != nil
        case .window:
            model.canUseRecordButton && effectiveCaptureTarget(kind: .window) != nil
        case .area:
            model.canSelectArea
        case .audio:
            model.canUseAudioOnlyButton
        }
    }

    private var recordButtonCanRecover: Bool {
        switch captureMode {
        case .display, .window, .area:
            model.sourcePermissionPresentation(for: .screenPixels).needsSetup
        case .audio:
            audioCaptureRecoverySource() != nil
        }
    }

    private var recordButtonHelp: String {
        model.hasActiveRecording ? "Stop recording" : idleRecordDescription
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
        let microphone = model.sourcePermissionPresentation(for: .microphone)
        let systemAudio = model.sourcePermissionPresentation(for: .systemAudio)

        if microphone.needsSetup {
            return .microphone
        }

        if systemAudio.needsSetup {
            return .systemAudio
        }

        if microphone.phase == .offByUser {
            return .microphone
        }

        if systemAudio.phase == .offByUser {
            return .systemAudio
        }

        return nil
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
