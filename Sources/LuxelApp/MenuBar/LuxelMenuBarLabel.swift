import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.recordingPresentation(now: now)
        let title = menuBarTitle(for: presentation)

        HStack(spacing: 4) {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
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
    let animates: Bool
    @State private var displayedSystemImage: String?
    @State private var outgoingSystemImage: String?
    @State private var transitionProgress: CGFloat = 1

    var body: some View {
        ZStack {
            if let outgoingSystemImage {
                icon(outgoingSystemImage)
                    .opacity(Double(1 - transitionProgress))
                    .scaleEffect(1 - transitionProgress * 0.08)
            }

            icon(displayedSystemImage ?? systemImage)
                .opacity(Double(transitionProgress))
                .scaleEffect(0.88 + transitionProgress * 0.12)
        }
            .frame(width: 18, height: 18)
            .onAppear {
                displayedSystemImage = systemImage
                transitionProgress = 1
            }
            .onChange(of: systemImage) { _, newValue in
                transition(to: newValue)
            }
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
    }

    private func transition(to newValue: String) {
        guard displayedSystemImage != newValue else {
            return
        }

        outgoingSystemImage = displayedSystemImage ?? systemImage
        displayedSystemImage = newValue
        transitionProgress = 0

        withAnimation(.easeInOut(duration: animates ? 0.34 : 0.24)) {
            transitionProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            if displayedSystemImage == newValue {
                outgoingSystemImage = nil
            }
        }
    }
}
