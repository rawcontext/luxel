import AppKit
import CoreGraphics
import LuxelCore

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
                style: RecordingFrameStyle(
                    target: request.target,
                    frame: frame,
                    screen: screen(containing: frame)
                )
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
        let contentView = RecordingFrameDrawingView(style: style)
        contentView.frame = NSRect(origin: .zero, size: frame.size)
        panel.contentView = contentView
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

    init(target: CaptureTarget, frame: NSRect, screen: NSScreen?) {
        switch target {
        case .display:
            self = .fullDisplay(cornerRadii: Self.fullDisplayCornerRadii(screen: screen))
        case .area where screen.map({ frame.matches($0.frame) }) == true:
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

private final class RecordingFrameDrawingView: NSView {
    private let style: RecordingFrameStyle

    init(style: RecordingFrameStyle) {
        self.style = style
        super.init(frame: .zero)
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        let strokeWidth: CGFloat = 3
        let path: NSBezierPath

        switch style {
        case .fullDisplay(let cornerRadii):
            path = roundedRectanglePath(
                in: bounds.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2),
                cornerRadii: cornerRadii
            )
        case .selection:
            path = roundedRectanglePath(
                in: bounds.insetBy(dx: strokeWidth / 2 + 2, dy: strokeWidth / 2 + 2),
                cornerRadii: RecordingFrameCornerRadii(top: 6, bottom: 6)
            )
        }

        path.lineWidth = strokeWidth
        NSColor.red.withAlphaComponent(0.86).setStroke()
        path.stroke()
    }

    private func roundedRectanglePath(
        in rect: NSRect,
        cornerRadii: RecordingFrameCornerRadii
    ) -> NSBezierPath {
        let radius = clampedRadius(max(cornerRadii.top, cornerRadii.bottom), in: rect)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func clampedRadius(_ radius: CGFloat, in rect: NSRect) -> CGFloat {
        min(max(radius, 0), rect.width / 2, rect.height / 2)
    }
}

private extension NSRect {
    func matches(_ other: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
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
