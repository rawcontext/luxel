import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let title = menuBarTitle(for: presentation)
        let pulseValue = presentation.animatesMenuBarSystemImage ? Int(now.timeIntervalSinceReferenceDate) : 0

        HStack(spacing: 4) {
            Image(systemName: presentation.menuBarSystemImage)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, value: pulseValue)
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
