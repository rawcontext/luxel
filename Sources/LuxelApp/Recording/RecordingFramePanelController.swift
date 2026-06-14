import AppKit
import CoreGraphics
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
        panels = frames.map { frame in
            makePanel(
                frame: frame,
                style: RecordingFrameStyle(target: request.target, screen: screen(containing: frame))
            )
        }
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

    private func makePanel(frame: NSRect, style: RecordingFrameStyle) -> NSPanel {
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
        panel.contentView = NSHostingView(rootView: RecordingFrameView(style: style))
        return panel
    }

    private func screen(containing frame: NSRect) -> NSScreen? {
        let midpoint = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(midpoint) }
    }

}

private enum RecordingFrameStyle {
    case fullDisplay(cornerRadii: RecordingFrameCornerRadii)
    case selection

    init(target: CaptureTarget, screen: NSScreen?) {
        switch target {
        case .display:
            self = .fullDisplay(cornerRadii: Self.fullDisplayCornerRadii(screen: screen))
        case .area, .window:
            self = .selection
        }
    }

    private static func fullDisplayCornerRadii(screen: NSScreen?) -> RecordingFrameCornerRadii {
        guard let screen, screen.isBuiltInDisplay, screen.safeAreaInsets.top > 0 else {
            return .square
        }

        // AppKit exposes notched built-in displays through safeAreaInsets, but not physical corner radius.
        let cornerRadius = min(max(screen.safeAreaInsets.top * 0.65, 18), 28)
        return RecordingFrameCornerRadii(top: cornerRadius, bottom: cornerRadius)
    }
}

private struct RecordingFrameCornerRadii {
    let top: CGFloat
    let bottom: CGFloat

    static let square = RecordingFrameCornerRadii(top: 0, bottom: 0)
}

private struct RecordingFrameView: View {
    let style: RecordingFrameStyle

    var body: some View {
        Group {
            switch style {
            case .fullDisplay(let cornerRadii):
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadii.top,
                    bottomLeadingRadius: cornerRadii.bottom,
                    bottomTrailingRadius: cornerRadii.bottom,
                    topTrailingRadius: cornerRadii.top,
                    style: .continuous
                )
                .strokeBorder(.red.opacity(0.86), lineWidth: 3)

            case .selection:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.red.opacity(0.86), lineWidth: 3)
                    .padding(2)
            }
        }
        .background(Color.clear)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private extension NSScreen {
    var isBuiltInDisplay: Bool {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }

        return CGDisplayIsBuiltin(screenNumber.uint32Value) != 0
    }
}
