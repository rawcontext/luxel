import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        Image(systemName: presentation.menuBarSystemImage)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating, isActive: presentation.animatesMenuBarSystemImage)
            .animation(.easeInOut(duration: 0.22), value: presentation.menuBarSystemImage)
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
