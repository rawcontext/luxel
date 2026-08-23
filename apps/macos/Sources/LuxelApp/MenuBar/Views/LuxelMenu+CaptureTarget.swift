import LuxelCore
import SwiftUI

extension LuxelMenu {
    @ViewBuilder
    var captureTargetChip: some View {
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

    func captureTargetChipMenu(
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

    func captureTargetChipLabel(
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

    var areaTargetChipText: String {
        if let memory = model.settings.lastCaptureMemory,
            case .area = memory.target
        {
            return "\(memory.pixelSize.width) × \(memory.pixelSize.height) · reselect at record"
        }

        return "Choose area at record"
    }

    var audioTargetChipText: String {
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

    func captureTargetSelection(_ target: CaptureTargetOption) -> Binding<Bool> {
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

    func effectiveCaptureTarget(kind: CaptureTargetKind) -> CaptureTargetOption? {
        if let selected = model.selectedCaptureTarget, selected.kind == kind {
            return selected
        }

        return model.captureTargets.first { $0.kind == kind }
    }

    var recordButtonIsEnabled: Bool {
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

    var recordButtonCanStart: Bool {
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

    var recordButtonCanRecover: Bool {
        switch captureMode {
        case .display, .window, .area:
            model.sourcePermissionPresentation(for: .screenPixels).needsSetup
        case .audio:
            audioCaptureRecoverySource() != nil
        }
    }

    var recordButtonHelp: String {
        model.hasActiveRecording ? "Stop recording" : idleRecordDescription
    }

}
