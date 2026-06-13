import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let systemImage = presentation.alternateMenuBarSystemImage ?? presentation.menuBarSystemImage

        Image(systemName: systemImage)
            .contentTransition(.symbolEffect(.replace))
            .animation(.easeInOut(duration: 0.2), value: systemImage)
            .accessibilityLabel(Text(presentation.accessibilityLabel))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
    }
}
