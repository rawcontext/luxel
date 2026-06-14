import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation()

        Label {
            Text(presentation.accessibilityLabel)
        } icon: {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
                isPulsing: presentation.animatesMenuBarSystemImage
            )
        }
            .labelStyle(.iconOnly)
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let isPulsing: Bool

    @State private var displayedSystemImage: String
    @State private var previousSystemImage: String?
    @State private var transitionProgress = 1.0
    @State private var pulseActivation = 0.0

    init(systemImage: String, isPulsing: Bool) {
        self.systemImage = systemImage
        self.isPulsing = isPulsing
        _displayedSystemImage = State(initialValue: systemImage)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPulsing)) { context in
            ZStack {
                if let previousSystemImage {
                    statusImage(previousSystemImage)
                        .opacity(1 - transitionProgress)
                        .scaleEffect(1 - (transitionProgress * 0.08))
                }

                statusImage(displayedSystemImage)
                    .opacity(transitionProgress)
                    .scaleEffect(0.92 + (transitionProgress * 0.08))

                if isPulsing || pulseActivation > 0 {
                    let pulse = Self.pulseAmount(at: context.date)

                    statusImage("record.circle.fill")
                        .opacity(pulseActivation * (0.18 + (pulse * 0.72)))
                        .scaleEffect(0.96 + (pulse * 0.06))
                }
            }
            .frame(width: 18, height: 18)
        }
        .onAppear {
            pulseActivation = isPulsing ? 1 : 0
        }
        .onChange(of: isPulsing) { _, newValue in
            withAnimation(.smooth(duration: 0.24)) {
                pulseActivation = newValue ? 1 : 0
            }
        }
        .onChange(of: systemImage) { _, newSystemImage in
            guard newSystemImage != displayedSystemImage else {
                return
            }

            previousSystemImage = displayedSystemImage
            displayedSystemImage = newSystemImage
            transitionProgress = 0
            withAnimation(.smooth(duration: 0.24)) {
                transitionProgress = 1
            }
        }
    }

    private func statusImage(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.primary)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
    }

    private static func pulseAmount(at date: Date) -> Double {
        let cycleDuration = 1.25
        let cycle = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration

        return 0.5 - (cos(cycle * 2 * .pi) * 0.5)
    }
}
