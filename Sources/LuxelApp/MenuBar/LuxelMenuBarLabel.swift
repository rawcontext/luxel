import Foundation
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
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}
