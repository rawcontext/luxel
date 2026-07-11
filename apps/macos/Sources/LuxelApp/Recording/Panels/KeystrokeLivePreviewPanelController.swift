import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class KeystrokeLivePreviewPanelController {
    private let makePanel: () -> NSPanel
    private let registerWindow: (UInt32) async -> UUID
    private let unregisterWindow: (UUID) async -> Void
    private let orderFront: (NSPanel) -> Void
    private var panel: NSPanel?
    private var exclusionRegistrationID: UUID?
    private var presentationGeneration = 0

    init(exclusionRegistry: CaptureExclusionRegistry) {
        makePanel = Self.defaultPanel
        registerWindow = { windowID in
            await exclusionRegistry.register(windowID: windowID)
        }
        unregisterWindow = { registrationID in
            await exclusionRegistry.unregister(registrationID)
        }
        orderFront = { $0.orderFrontRegardless() }
    }

    init(
        makePanel: @escaping () -> NSPanel,
        registerWindow: @escaping (UInt32) async -> UUID,
        unregisterWindow: @escaping (UUID) async -> Void,
        orderFront: @escaping (NSPanel) -> Void
    ) {
        self.makePanel = makePanel
        self.registerWindow = registerWindow
        self.unregisterWindow = unregisterWindow
        self.orderFront = orderFront
    }

    func prepareForCapture(isEnabled: Bool) async {
        guard isEnabled, panel == nil else {
            return
        }

        let panel = makePanel()
        configure(panel)
        self.panel = panel
        let registrationID = await registerWindow(UInt32(panel.windowNumber))
        guard self.panel === panel else {
            await unregisterWindow(registrationID)
            return
        }
        exclusionRegistrationID = registrationID
        orderFront(panel)
    }

    func present(
        chips: [KeystrokeChip],
        options: KeystrokeRenderOptions,
        isEnabled: Bool
    ) async {
        guard isEnabled else {
            hide()
            return
        }
        guard options.isVisible, !chips.isEmpty else {
            hide()
            return
        }

        presentationGeneration += 1
        let generation = presentationGeneration

        guard let panel, exclusionRegistrationID != nil else {
            return
        }
        let content = KeystrokeChipStackView(chips: chips, options: options).padding(16)
        panel.contentView = NSHostingView(rootView: content)
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        position(panel, anchor: options.anchor)
        panel.alphaValue = 1
        scheduleClose(after: options.displayDuration, generation: generation)
    }

    private func configure(_ panel: NSPanel) {
        panel.setContentSize(NSSize(width: 1, height: 1))
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.alphaValue = 0
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
    }

    func close() async {
        presentationGeneration += 1
        panel?.orderOut(nil)
        panel = nil
        if let exclusionRegistrationID {
            await unregisterWindow(exclusionRegistrationID)
            self.exclusionRegistrationID = nil
        }
    }

    private func hide() {
        presentationGeneration += 1
        panel?.alphaValue = 0
    }

    private func position(_ panel: NSPanel, anchor: KeystrokeOverlayAnchor) {
        guard let screen = NSScreen.main else {
            panel.center()
            return
        }
        let origin = KeystrokeOverlayLayout.origin(
            overlaySize: panel.frame.size,
            frameSize: screen.visibleFrame.size,
            anchor: anchor
        )
        panel.setFrameOrigin(
            CGPoint(
                x: screen.visibleFrame.minX + origin.x,
                y: screen.visibleFrame.minY + origin.y
            )
        )
    }

    private func scheduleClose(after duration: TimeInterval, generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, presentationGeneration == generation else {
                return
            }
            hide()
        }
    }

    private static func defaultPanel() -> NSPanel {
        NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
    }
}
