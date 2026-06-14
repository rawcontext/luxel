import AppKit
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
                accessibilityLabel: presentation.accessibilityLabel
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
    let accessibilityLabel: String

    @State private var displayedSystemImage: String
    @State private var previousSystemImage: String?
    @State private var transitionProgress = 1.0

    init(systemImage: String, accessibilityLabel: String) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        _displayedSystemImage = State(initialValue: systemImage)
    }

    var body: some View {
        ZStack {
            if let previousSystemImage {
                statusImage(previousSystemImage)
                    .opacity(1 - transitionProgress)
                    .scaleEffect(1 - (transitionProgress * 0.08))
            }

            statusImage(displayedSystemImage)
                .opacity(transitionProgress)
                .scaleEffect(0.92 + (transitionProgress * 0.08))
        }
        .frame(width: 18, height: 18)
        .onChange(of: systemImage) { _, newSystemImage in
            guard newSystemImage != displayedSystemImage else {
                return
            }

            previousSystemImage = displayedSystemImage
            displayedSystemImage = newSystemImage
            transitionProgress = 0
            withAnimation(.easeInOut(duration: 0.24)) {
                transitionProgress = 1
            }
        }
    }

    private func statusImage(_ systemImage: String) -> some View {
        Image(nsImage: menuBarImage(systemImage))
            .resizable()
            .scaledToFit()
    }

    private func menuBarImage(_ systemImage: String) -> NSImage {
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: accessibilityLabel)
            ?? NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Luxel")
            ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }
}
