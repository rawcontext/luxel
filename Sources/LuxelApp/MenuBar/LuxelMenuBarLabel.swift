import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        Image(systemName: presentation.menuBarSystemImage)
            .frame(width: 18, height: 18)
            .symbolEffect(
                .pulse,
                options: .repeat(.continuous).speed(0.72),
                isActive: presentation.animatesMenuBarSystemImage
            )
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
    }
}
