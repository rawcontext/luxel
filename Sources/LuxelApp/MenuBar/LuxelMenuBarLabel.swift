import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation(now: now)

        MenuBarStatusIcon(
            systemImage: presentation.menuBarSystemImage,
            animates: presentation.animatesMenuBarSystemImage
        )
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
}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let animates: Bool

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: animates)
            .animation(.easeInOut(duration: 0.24), value: systemImage)
    }
}
