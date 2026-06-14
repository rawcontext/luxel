import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var recordingPulseOpacity = 1.0
    @State private var recordingPulseScale = 1.0
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let title = menuBarTitle(for: presentation)
        let isRecordingAnimationActive = presentation.animatesMenuBarSystemImage

        HStack(spacing: 4) {
            Image(systemName: presentation.menuBarSystemImage)
                .font(.system(size: 14, weight: .regular))
                .imageScale(.medium)
                .frame(width: 18, height: 18)
                .contentTransition(.symbolEffect(.replace))
                .scaleEffect(isRecordingAnimationActive ? recordingPulseScale : 1.0)
                .opacity(isRecordingAnimationActive ? recordingPulseOpacity : 1.0)
                .animation(.easeInOut(duration: 0.2), value: presentation.menuBarSystemImage)

            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        }
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
            .task {
                await model.keepCaptureTargetCacheWarm()
            }
            .task(id: isRecordingAnimationActive) {
                await runRecordingPulse(isAnimating: isRecordingAnimationActive)
            }
    }

    private func menuBarTitle(for presentation: RecordingSessionPresentation) -> String? {
        switch presentation.menuBarTitle {
        case "", "Luxel":
            nil
        default:
            presentation.menuBarTitle
        }
    }

    @MainActor
    private func runRecordingPulse(isAnimating: Bool) async {
        guard isAnimating else {
            withAnimation(.easeOut(duration: 0.18)) {
                recordingPulseOpacity = 1.0
                recordingPulseScale = 1.0
            }
            return
        }

        recordingPulseOpacity = 0.86
        recordingPulseScale = 0.96

        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.85)) {
                recordingPulseOpacity = 1.0
                recordingPulseScale = 1.08
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else {
                break
            }

            withAnimation(.easeInOut(duration: 0.85)) {
                recordingPulseOpacity = 0.86
                recordingPulseScale = 0.96
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
        }
    }
}
