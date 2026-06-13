import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var pulsePhase = false

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let systemImage = systemImage(for: presentation)

        Image(systemName: systemImage)
            .contentTransition(.symbolEffect)
            .animation(.easeInOut(duration: 0.2), value: systemImage)
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
            .task(id: presentation.animatesMenuBarSystemImage) {
                guard presentation.animatesMenuBarSystemImage else {
                    pulsePhase = false
                    return
                }

                while !Task.isCancelled {
                    pulsePhase.toggle()
                    try? await Task.sleep(nanoseconds: 550_000_000)
                }
            }
    }

    private func systemImage(for presentation: RecordingSessionPresentation) -> String {
        guard pulsePhase, let alternateSystemImage = presentation.alternateMenuBarSystemImage else {
            return presentation.menuBarSystemImage
        }

        return alternateSystemImage
    }
}
