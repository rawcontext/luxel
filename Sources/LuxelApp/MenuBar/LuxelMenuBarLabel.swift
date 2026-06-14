import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation(now: now)
        let title = menuBarTitle(for: presentation)

        HStack(spacing: 4) {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
                animates: presentation.animatesMenuBarSystemImage
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

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let animates: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: animates)
            .animation(.easeInOut(duration: 0.22), value: systemImage)
            .frame(width: 18, height: 18)
    }
}
