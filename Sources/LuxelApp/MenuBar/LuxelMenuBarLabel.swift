import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation()

        MenuBarStatusIcon(
            systemImage: presentation.menuBarSystemImage,
            animates: presentation.animatesMenuBarSystemImage
        )
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
    let animates: Bool
    @State private var currentSystemImage: String
    @State private var previousSystemImage: String?
    @State private var showsCurrentImage = true
    @State private var pulseScale = 1.0
    @State private var transitionID = UUID()

    init(systemImage: String, animates: Bool) {
        self.systemImage = systemImage
        self.animates = animates
        _currentSystemImage = State(initialValue: systemImage)
    }

    var body: some View {
        ZStack {
            if let previousSystemImage {
                symbol(previousSystemImage)
                    .opacity(showsCurrentImage ? 0 : 1)
                    .scaleEffect(showsCurrentImage ? 0.92 : 1)
            }

            symbol(currentSystemImage)
                .opacity(showsCurrentImage ? 1 : 0)
                .scaleEffect((showsCurrentImage ? 1 : 1.08) * pulseScale)
        }
        .frame(width: 18, height: 18)
        .clipped()
        .onAppear {
            updatePulse(animated: false)
        }
        .onChange(of: systemImage) { _, newValue in
            transition(to: newValue)
        }
        .onChange(of: animates) {
            updatePulse(animated: true)
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
    }

    private func transition(to newSystemImage: String) {
        guard currentSystemImage != newSystemImage else {
            return
        }

        previousSystemImage = currentSystemImage
        currentSystemImage = newSystemImage
        showsCurrentImage = false

        let transitionID = UUID()
        self.transitionID = transitionID
        withAnimation(.easeInOut(duration: 0.24)) {
            showsCurrentImage = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            guard self.transitionID == transitionID else {
                return
            }
            previousSystemImage = nil
        }
    }

    private func updatePulse(animated: Bool) {
        guard animates else {
            withAnimation(animated ? .easeOut(duration: 0.18) : nil) {
                pulseScale = 1
            }
            return
        }

        pulseScale = 0.96
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulseScale = 1.06
        }
    }
}
