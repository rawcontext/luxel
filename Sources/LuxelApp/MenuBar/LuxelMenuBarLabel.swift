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
            }

            symbol(currentSystemImage)
                .opacity(showsCurrentImage ? 1 : 0)
                .symbolEffect(.pulse, options: .repeating, isActive: animates)
        }
        .frame(width: 18, height: 18)
        .onChange(of: systemImage) { _, newValue in
            transition(to: newValue)
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
}
