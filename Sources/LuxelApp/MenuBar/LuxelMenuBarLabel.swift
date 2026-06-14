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

        HStack(spacing: 4) {
            Image(systemName: presentation.menuBarSystemImage)
                .contentTransition(.symbolEffect(.replace))
                .opacity(presentation.animatesMenuBarSystemImage && !isRecordingPulseActive ? 0.58 : 1)
                .scaleEffect(presentation.animatesMenuBarSystemImage && isRecordingPulseActive ? 1.08 : 1)
                .animation(.easeInOut(duration: 0.24), value: presentation.menuBarSystemImage)

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
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isRecordingPulseActive = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                isRecordingPulseActive = false
            }
        }
    }
}
