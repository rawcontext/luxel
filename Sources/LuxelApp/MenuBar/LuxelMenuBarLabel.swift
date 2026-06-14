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

    var body: some View {
        Group {
            if systemImage == "record.circle" {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isRecording)) { timeline in
                    let phase = isRecording ? pulsePhase(at: timeline.date) : 0
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 1.6)
                            .opacity(isRecording ? 0.82 : 0.9)

                        Circle()
                            .fill()
                            .frame(width: 6.2, height: 6.2)
                            .scaleEffect(isRecording ? 0.82 + phase * 0.28 : 0.72)
                            .opacity(isRecording ? 0.72 + phase * 0.28 : 0.9)

                        if isRecording {
                            Circle()
                                .stroke(lineWidth: 1.1)
                                .scaleEffect(0.68 + phase * 0.3)
                                .opacity(0.34 - phase * 0.22)
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: isRecording)
                }
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .imageScale(.medium)
            }
        }
        .frame(width: 18, height: 18)
    }

    private func pulsePhase(at date: Date) -> CGFloat {
        let cycle = 1.45
        let progress = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycle) / cycle
        return CGFloat((1 - cos(progress * 2 * .pi)) / 2)
    }
}
