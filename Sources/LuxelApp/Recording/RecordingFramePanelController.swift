import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class RecordingFramePanelController {
    private var panels: [NSPanel] = []
    private var registrationID: UUID?
    private var exclusionRegistry: CaptureExclusionRegistry?

    func present(
        for request: RecordingRequest,
        availableTargets: [CaptureTargetOption],
        exclusionRegistry: CaptureExclusionRegistry
    ) async {
        await close()

        let frames = CaptureTargetScreenRectResolver.rects(
            for: request.target,
            availableTargets: availableTargets
        )
        guard !frames.isEmpty else {
            return
        }

        self.exclusionRegistry = exclusionRegistry
        panels = frames.map(makePanel(frame:))
        panels.forEach { $0.orderFrontRegardless() }

        let windowIDs = panels.compactMap { panel -> UInt32? in
            guard panel.windowNumber > 0 else {
                return nil
            }

            return UInt32(panel.windowNumber)
        }
        registrationID = await exclusionRegistry.register(windowIDs: windowIDs)
    }

    func close() async {
        if let registrationID, let exclusionRegistry {
            await exclusionRegistry.unregister(registrationID)
        }

        panels.forEach { $0.close() }
        panels = []
        self.registrationID = nil
        self.exclusionRegistry = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: RecordingFrameView())
        return panel
    }

}

private struct RecordingFrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(.red.opacity(0.86), lineWidth: 3)
            .background(Color.clear)
            .padding(2)
            .allowsHitTesting(false)
    }
}
