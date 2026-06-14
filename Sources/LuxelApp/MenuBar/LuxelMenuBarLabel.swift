import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let title = menuBarTitle(for: presentation)
        let isRecordingAnimationActive = presentation.animatesMenuBarSystemImage

        HStack(spacing: 4) {
            MenuBarRecordingIcon(
                systemImage: presentation.menuBarSystemImage,
                isRecording: isRecordingAnimationActive
            )

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
    }

    private func menuBarTitle(for presentation: RecordingSessionPresentation) -> String? {
        switch presentation.menuBarTitle {
        case "", "Luxel":
            nil
        default:
            presentation.menuBarTitle
        }
    }

}

private struct MenuBarRecordingIcon: View {
    let systemImage: String
    let isRecording: Bool
    @State private var isPulseExpanded = false

    var body: some View {
        Group {
            if systemImage == "record.circle" {
                ZStack {
                    Circle()
                        .stroke(lineWidth: 1.6)
                        .opacity(isRecording ? 0.82 : 0.9)

                    Circle()
                        .fill()
                        .frame(width: 6.2, height: 6.2)
                        .scaleEffect(isRecording ? (isPulseExpanded ? 1.1 : 0.82) : 0.72)
                        .opacity(isRecording ? (isPulseExpanded ? 1 : 0.72) : 0.9)

                    if isRecording {
                        Circle()
                            .stroke(lineWidth: 1.1)
                            .scaleEffect(isPulseExpanded ? 0.98 : 0.68)
                            .opacity(isPulseExpanded ? 0.12 : 0.34)
                    }
                }
                .onAppear {
                    updatePulseAnimation(isRecording: isRecording)
                }
                .onChange(of: isRecording) { _, newValue in
                    updatePulseAnimation(isRecording: newValue)
                }
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .imageScale(.medium)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func updatePulseAnimation(isRecording: Bool) {
        if isRecording {
            isPulseExpanded = false
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulseExpanded = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                isPulseExpanded = false
            }
        }
    }
}
