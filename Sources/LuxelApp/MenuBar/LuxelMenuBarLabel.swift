import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation(now: now)
        let title = menuBarTitle(for: presentation)

        HStack(spacing: 4) {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
                alternateSystemImage: presentation.alternateMenuBarSystemImage,
                animates: presentation.animatesMenuBarSystemImage
            )

            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        }
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

    private func menuBarTitle(for presentation: RecordingSessionPresentation) -> String? {
        switch presentation.menuBarTitle {
        case "", "Luxel":
            nil
        default:
            presentation.menuBarTitle
        }
    }

}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let alternateSystemImage: String?
    let animates: Bool

    @ViewBuilder
    var body: some View {
        if animates, let alternateSystemImage {
            TimelineView(.periodic(from: .now, by: 1.1)) { timeline in
                let showsAlternateImage = showsAlternateImage(at: timeline.date)

                ZStack {
                    icon(systemImage)
                        .opacity(showsAlternateImage ? 0.18 : 1)
                        .scaleEffect(showsAlternateImage ? 0.86 : 1)

                    icon(alternateSystemImage)
                        .opacity(showsAlternateImage ? 1 : 0)
                        .scaleEffect(showsAlternateImage ? 1 : 0.86)
                }
                .animation(.easeInOut(duration: 0.55), value: showsAlternateImage)
            }
            .frame(width: 18, height: 18)
        } else {
            icon(systemImage)
                .frame(width: 18, height: 18)
        }
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
    }

    private func showsAlternateImage(at date: Date) -> Bool {
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)
        return cycle >= 1.1
    }
}
