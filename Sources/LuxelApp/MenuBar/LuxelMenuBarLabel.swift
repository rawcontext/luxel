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
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .imageScale(.medium)
                .id(systemImage)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .frame(width: 18, height: 18)
        .scaleEffect(animates && isPulsing ? 0.9 : 1)
        .opacity(animates && isPulsing ? 0.58 : 1)
        .animation(.easeInOut(duration: 0.24), value: systemImage)
        .onAppear(perform: updatePulse)
        .onChange(of: animates) {
            updatePulse()
        }
    }

    private func updatePulse() {
        if animates {
            isPulsing = false
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                isPulsing = false
            }
        }
    }
}
