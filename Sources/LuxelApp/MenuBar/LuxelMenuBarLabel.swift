import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var pulsePhase = false

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        ZStack {
            Image(systemName: presentation.menuBarSystemImage)
                .opacity(primarySymbolOpacity(for: presentation))

            if let alternateMenuBarSystemImage = presentation.alternateMenuBarSystemImage {
                Image(systemName: alternateMenuBarSystemImage)
                    .opacity(alternateSymbolOpacity(for: presentation))
            }
        }
            .frame(width: 18, height: 18)
            .animation(.easeInOut(duration: 0.45), value: pulsePhase)
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

                pulsePhase = false

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    pulsePhase.toggle()
                }
            }
    }

    private func primarySymbolOpacity(for presentation: RecordingSessionPresentation) -> Double {
        guard presentation.animatesMenuBarSystemImage,
              presentation.alternateMenuBarSystemImage != nil else {
            return 1
        }

        return pulsePhase ? 0 : 1
    }

    private func alternateSymbolOpacity(for presentation: RecordingSessionPresentation) -> Double {
        guard presentation.animatesMenuBarSystemImage else {
            return 0
        }

        return pulsePhase ? 1 : 0
    }
}
