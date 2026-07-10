import AVFoundation
import AppKit
import LuxelCore

enum CameraPreviewPanelError: Error {
    case cannotAddInput
    case sessionInterrupted
    case deviceDisconnected
}

struct CameraCaptureSessionHandle: @unchecked Sendable {
    let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }

    func stopRunningIfNeeded() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

final class CameraPreviewPanelView: NSView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var cutoutLayer: CameraCutoutPreviewLayer?
    private let glassBorderLayer = CALayer()
    private let glassHighlightLayer = CALayer()
    private let closeButton = NSButton(frame: .zero)
    private let isMirrored: Bool
    private var effectiveShape: CameraOverlayShape
    private let snapOrigin: (NSRect) -> NSPoint
    private let onMove: (NSRect) -> Void
    private let onClose: @MainActor () -> Void
    private var trackingArea: NSTrackingArea?
    private var dragStartPoint: NSPoint?
    private var dragStartFrame: NSRect?
    private var showsHoverControls: Bool
    private var isMouseInside = false

    init(
        session: AVCaptureSession,
        style: CameraPreviewStyle,
        showsHoverControls: Bool,
        snapOrigin: @escaping (NSRect) -> NSPoint,
        onMove: @escaping (NSRect) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.previewLayer = style.shape.usesPortraitMatting
            ? nil
            : AVCaptureVideoPreviewLayer(session: session)
        self.cutoutLayer = style.shape.usesPortraitMatting ? CameraCutoutPreviewLayer() : nil
        self.isMirrored = style.isMirrored
        self.effectiveShape = style.shape
        self.showsHoverControls = showsHoverControls
        self.snapOrigin = snapOrigin
        self.onMove = onMove
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        if let previewLayer {
            configurePreviewLayer(previewLayer)
            layer?.addSublayer(previewLayer)
        }
        if let cutoutLayer {
            layer?.addSublayer(cutoutLayer)
        }
        configureGlassBorderLayers()
        glassBorderLayer.isHidden = style.shape.usesPortraitMatting
        glassHighlightLayer.isHidden = style.shape.usesPortraitMatting
        layer?.addSublayer(glassBorderLayer)
        layer?.addSublayer(glassHighlightLayer)
        configureCloseButton()
        addSubview(closeButton)
        updateHoverControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let cornerRadius = effectiveShape.cornerRadius(for: bounds.size)

        previewLayer?.frame = bounds
        previewLayer?.cornerRadius = cornerRadius
        previewLayer?.cornerCurve = .continuous
        previewLayer?.masksToBounds = true
        cutoutLayer?.frame = bounds
        closeButton.frame = closeButtonFrame()
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false

        layoutGlassLayer(glassBorderLayer, inset: 0, cornerRadius: cornerRadius)
        layoutGlassLayer(glassHighlightLayer, inset: 2, cornerRadius: cornerRadius)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseInside = true
        updateHoverControls()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseInside = false
        updateHoverControls()
    }

    func setHoverControlsEnabled(_ isEnabled: Bool) {
        showsHoverControls = isEnabled
        updateHoverControls()
    }

    func detachPreviewSession() {
        previewLayer?.session = nil
        cutoutLayer?.clear()
    }

    func presentCutout(_ image: CGImage) {
        cutoutLayer?.present(image)
    }

    func showDirectFallback(session: AVCaptureSession) {
        cutoutLayer?.clear()
        cutoutLayer?.removeFromSuperlayer()
        cutoutLayer = nil
        effectiveShape = .circle
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        configurePreviewLayer(previewLayer)
        layer?.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        glassBorderLayer.isHidden = false
        glassHighlightLayer.isHidden = false
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = window?.convertPoint(toScreen: event.locationInWindow)
        dragStartFrame = window?.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let dragStartPoint,
              let dragStartFrame
        else {
            return
        }

        let point = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(
            x: point.x - dragStartPoint.x,
            y: point.y - dragStartPoint.y
        )
        window.setFrameOrigin(
            NSPoint(
                x: dragStartFrame.origin.x + delta.x,
                y: dragStartFrame.origin.y + delta.y
            ))
    }

    override func mouseUp(with event: NSEvent) {
        if let window {
            let snappedOrigin = snapOrigin(window.frame)
            window.setFrameOrigin(snappedOrigin)
            onMove(NSRect(origin: snappedOrigin, size: window.frame.size))
        }

        dragStartPoint = nil
        dragStartFrame = nil
    }

    private func configureCloseButton() {
        closeButton.bezelStyle = .circular
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(
            systemSymbolName: "xmark", accessibilityDescription: "Close Camera Preview")
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closePreview)
        closeButton.toolTip = "Close Camera Preview"
    }

    private func configurePreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer) {
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.transform =
            isMirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    private func configureGlassBorderLayers() {
        glassBorderLayer.backgroundColor = NSColor.clear.cgColor
        glassBorderLayer.borderWidth = 2
        glassBorderLayer.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
        glassBorderLayer.shadowColor = NSColor.white.cgColor
        glassBorderLayer.shadowOpacity = 0.16
        glassBorderLayer.shadowRadius = 12
        glassBorderLayer.shadowOffset = .zero

        glassHighlightLayer.backgroundColor = NSColor.clear.cgColor
        glassHighlightLayer.borderWidth = 1
        glassHighlightLayer.borderColor = NSColor.white.withAlphaComponent(0.36).cgColor
    }

    private func layoutGlassLayer(_ layer: CALayer, inset: CGFloat, cornerRadius: CGFloat) {
        layer.frame = bounds.insetBy(dx: inset, dy: inset)
        layer.cornerRadius = max(0, cornerRadius - inset)
        layer.cornerCurve = .continuous
    }

    private func closeButtonFrame() -> NSRect {
        let buttonSize = CGSize(width: 24, height: 24)

        return NSRect(
            x: bounds.maxX - buttonSize.width - 8,
            y: bounds.maxY - buttonSize.height - 8,
            width: buttonSize.width,
            height: buttonSize.height
        )
    }

    private func updateHoverControls() {
        closeButton.isHidden = !(showsHoverControls && isMouseInside)
    }

    @objc private func closePreview() {
        onClose()
    }
}

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

extension CameraPreviewPlacement {
    init(point: NSPoint) throws {
        try self.init(x: Double(point.x), y: Double(point.y))
    }

    var point: NSPoint {
        NSPoint(x: xPosition, y: yPosition)
    }
}

extension CameraPreviewSize {
    var panelSize: CGSize {
        switch self {
        case .small:
            CGSize(width: 168, height: 168)
        case .medium:
            CGSize(width: 232, height: 232)
        case .large:
            CGSize(width: 312, height: 312)
        }
    }
}

extension CameraOverlayShape {
    func cornerRadius(for size: CGSize) -> CGFloat {
        switch self {
        case .circle:
            min(size.width, size.height) * 0.18
        case .roundedRect:
            16
        case .square, .cutout:
            0
        }
    }
}

extension CameraPreviewStyle {
    func replacingShape(_ shape: CameraOverlayShape) -> CameraPreviewStyle {
        CameraPreviewStyle(shape: shape, size: size, isMirrored: isMirrored)
    }
}
