import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation()

        Label(presentation.accessibilityLabel, systemImage: presentation.menuBarSystemImage)
            .labelStyle(.iconOnly)
            .imageScale(.medium)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: presentation.animatesMenuBarSystemImage)
            .animation(.smooth(duration: 0.24), value: presentation.menuBarSystemImage)
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}
