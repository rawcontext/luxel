import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation()

        Label {
            Text(presentation.accessibilityLabel)
        } icon: {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
                isAnimating: presentation.animatesMenuBarSystemImage
            )
        }
            .labelStyle(.iconOnly)
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let isAnimating: Bool

    var body: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: isAnimating)
            .frame(width: 18, height: 18)
            .animation(.smooth(duration: 0.24), value: systemImage)
    }
}
