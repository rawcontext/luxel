import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var isRecordingPulseActive = false
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let title = menuBarTitle(for: presentation)
        let isRecordingAnimationActive = presentation.animatesMenuBarSystemImage

        HStack(spacing: 4) {
            Image(systemName: presentation.menuBarSystemImage)
                .scaleEffect(isRecordingAnimationActive ? (isRecordingPulseActive ? 1.1 : 0.96) : 1)
                .opacity(isRecordingAnimationActive && !isRecordingPulseActive ? 0.86 : 1)
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
            .onAppear {
                updateRecordingPulse(isAnimating: presentation.animatesMenuBarSystemImage)
            }
            .onChange(of: presentation.animatesMenuBarSystemImage) { _, isAnimating in
                updateRecordingPulse(isAnimating: isAnimating)
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

    private func updateRecordingPulse(isAnimating: Bool) {
        if isAnimating {
            isRecordingPulseActive = false
            withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                isRecordingPulseActive = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                isRecordingPulseActive = false
            }
        }
    }
}
