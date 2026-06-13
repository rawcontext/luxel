import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)

        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: !presentation.animatesMenuBarSystemImage
            )
        ) { timeline in
            let blend = blendValue(for: presentation, at: timeline.date)

            ZStack {
                Image(systemName: presentation.menuBarSystemImage)
                    .opacity(1 - blend)

                if let alternateMenuBarSystemImage = presentation.alternateMenuBarSystemImage {
                    Image(systemName: alternateMenuBarSystemImage)
                        .opacity(blend)
                }
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                now = Date()
            }
        }
    }

    private func blendValue(for presentation: RecordingSessionPresentation, at date: Date) -> Double {
        guard presentation.animatesMenuBarSystemImage,
              presentation.alternateMenuBarSystemImage != nil else {
            return 0
        }

        let period = 1.1
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period

        return (1 - cos(phase * 2 * .pi)) / 2
    }
}
