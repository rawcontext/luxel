import AppKit
import LuxelCore

@MainActor
final class RecordingFramePanelController {
    private var window: NSWindow?
    private var exclusionRegistry: CaptureExclusionRegistry?
    private var exclusionRegistrationID: UUID?

    func present(
        for request: RecordingRequest,
        availableTargets: [CaptureTargetOption],
        exclusionRegistry: CaptureExclusionRegistry
    ) async {
        await close()

        guard case .area = request.target,
            let frame = CaptureTargetScreenRectResolver.rect(
                for: request.target,
                availableTargets: availableTargets
            ),
            frame.width > 0,
            frame.height > 0
        else {
            return
        }

        let window = Self.makeWindow(frame: frame)
        window.orderFrontRegardless()

        self.window = window
        self.exclusionRegistry = exclusionRegistry
        exclusionRegistrationID = await exclusionRegistry.register(
            windowID: UInt32(window.windowNumber))
        try? await Task.sleep(for: .milliseconds(50))
    }

    func close() async {
        let registrationID = exclusionRegistrationID
        let registry = exclusionRegistry
        let window = window

        exclusionRegistrationID = nil
        exclusionRegistry = nil
        self.window = nil
        window?.orderOut(nil)

        if let registrationID {
            await registry?.unregister(registrationID)
        }
    }

    private static func makeWindow(frame: NSRect) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = RecordingAreaFrameView(frame: NSRect(origin: .zero, size: frame.size))
        return window
    }
}

private final class RecordingAreaFrameView: NSView {
    private let borderLayer = CALayer()
    private let highlightLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layoutBorderLayer(borderLayer, inset: 0, lineWidth: 2)
        layoutBorderLayer(highlightLayer, inset: 3, lineWidth: 1)
    }

    private func configureLayers() {
        borderLayer.backgroundColor = NSColor.clear.cgColor
        borderLayer.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        borderLayer.shadowColor = NSColor.white.cgColor
        borderLayer.shadowOpacity = 0.16
        borderLayer.shadowRadius = 12
        borderLayer.shadowOffset = .zero

        highlightLayer.backgroundColor = NSColor.clear.cgColor
        highlightLayer.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor

        layer?.addSublayer(borderLayer)
        layer?.addSublayer(highlightLayer)
    }

    private func layoutBorderLayer(_ layer: CALayer, inset: CGFloat, lineWidth: CGFloat) {
        let rect = bounds.insetBy(dx: inset, dy: inset)
        layer.frame = rect
        layer.borderWidth = lineWidth
        layer.cornerRadius = min(18, min(rect.width, rect.height) * 0.08)
        layer.cornerCurve = .continuous
    }
}
