import AVFoundation
import AppKit
import LuxelCore
import OSLog

@MainActor
final class CameraPreviewPanelController {
    private let sessionQueue = DispatchQueue(label: "app.luxel.cameraPreview.session")
    private let portraitMattingProcessorFactory: @MainActor () -> MODNetPortraitMattingProcessor?
    private var portraitMattingProcessor: MODNetPortraitMattingProcessor?
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var cutoutPipeline: CameraCutoutSessionPipeline?
    private var cutoutObserverTokens: [NSObjectProtocol] = []
    private var onCutoutFailure: (@MainActor () -> Void)?
    private var panelOriginsByDisplayID: [DisplayID: NSPoint] = [:]
    private var snapRect: NSRect?
    private var onPlacementChange: (@MainActor (DisplayID, CameraPreviewPlacement) -> Void)?

    init(
        portraitMattingProcessorFactory: @escaping @MainActor () -> MODNetPortraitMattingProcessor? = {
            nil
        }
    ) {
        self.portraitMattingProcessorFactory = portraitMattingProcessorFactory
    }

    func present(
        deviceID: String,
        style: CameraPreviewStyle,
        placements: [DisplayID: CameraPreviewPlacement] = [:],
        snapRect: NSRect? = nil,
        showsHoverControls: Bool = true,
        onPlacementChange: @escaping @MainActor (DisplayID, CameraPreviewPlacement) -> Void = { _, _ in
        },
        onCutoutFailure: @escaping @MainActor () -> Void = {},
        onClose: @escaping @MainActor () -> Void = {}
    ) {
        let preferredDisplayID = panel.flatMap { Self.screen(containing: $0.frame)?.displayID }
        close()
        panelOriginsByDisplayID = placements.mapValues(\.point)
        self.snapRect = snapRect
        self.onPlacementChange = onPlacementChange
        self.onCutoutFailure = onCutoutFailure

        guard let device = Self.captureDevice(deviceID: deviceID) else {
            NSSound.beep()
            return
        }

        do {
            let requestedCutout = style.shape.usesPortraitMatting
            let usesCutout = requestedCutout && portraitMattingProcessor?.isPrepared == true
            let effectiveStyle = requestedCutout && !usesCutout ? style.replacingShape(.circle) : style
            let cutoutPipeline = usesCutout
                ? makeCutoutPipeline(style: effectiveStyle)
                : nil
            let session = try Self.makeSession(
                device: device,
                videoOutput: cutoutPipeline?.videoOutput
            )
            let frame = panelFrame(
                size: effectiveStyle.size.panelSize,
                preferredDisplayID: preferredDisplayID
            )
            let panel = Self.makePanel(
                frame: frame,
                session: session,
                style: effectiveStyle,
                showsHoverControls: showsHoverControls,
                snapOrigin: { [weak self] frame in
                    Self.snappedOrigin(for: frame, snapRect: self?.snapRect)
                },
                onMove: { [weak self] frame in
                    self?.rememberPanelOrigin(frame: frame)
                },
                onClose: onClose
            )
            panel.orderFrontRegardless()

            self.session = session
            self.panel = panel
            self.cutoutPipeline = cutoutPipeline
            rememberPanelOrigin(frame: panel.frame)
            if let cutoutPipeline {
                observeCutoutFailures(session: session, device: device)
                cutoutPipeline.start()
            } else if style.shape.usesPortraitMatting {
                onCutoutFailure()
            }

            let sessionHandle = CameraCaptureSessionHandle(session)
            sessionQueue.async { [sessionHandle] in
                sessionHandle.session.startRunning()
            }
        } catch {
            NSSound.beep()
        }
    }

    func close() {
        guard let session = closePanelAndTakeSession() else {
            return
        }

        let sessionHandle = CameraCaptureSessionHandle(session)
        sessionQueue.async { [sessionHandle] in
            sessionHandle.stopRunningIfNeeded()
        }
    }

    func closeAndWaitForSessionStop() async {
        guard let session = closePanelAndTakeSession() else {
            return
        }

        await stopSession(session)
    }

    private func closePanelAndTakeSession() -> AVCaptureSession? {
        rememberPanelOrigin()
        cutoutPipeline?.stop()
        cutoutPipeline = nil
        removeCutoutObservers()
        (panel?.contentView as? CameraPreviewPanelView)?.detachPreviewSession()
        panel?.close()
        panel = nil
        snapRect = nil
        onPlacementChange = nil
        onCutoutFailure = nil

        let session = session
        self.session = nil
        return session
    }

    private func stopSession(_ session: AVCaptureSession) async {
        let sessionHandle = CameraCaptureSessionHandle(session)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [sessionHandle] in
                sessionHandle.stopRunningIfNeeded()
                continuation.resume()
            }
        }
    }

    func setHoverControlsEnabled(_ isEnabled: Bool) {
        (panel?.contentView as? CameraPreviewPanelView)?.setHoverControlsEnabled(isEnabled)
    }

    func setSnapRect(_ snapRect: NSRect?) {
        self.snapRect = snapRect

        guard let panel else {
            return
        }

        let constraintRect = constraintRect(for: panel.frame)
        let size = Self.constrainedPanelSize(panel.frame.size, in: constraintRect)
        let origin = Self.constrainedOrigin(
            panel.frame.origin,
            size: size,
            in: constraintRect
        )
        let frame = NSRect(origin: origin, size: size)
        guard frame != panel.frame else {
            return
        }

        panel.setFrame(frame, display: true)
        rememberPanelOrigin(frame: frame)
    }

    private static func makeSession(
        device: AVCaptureDevice,
        videoOutput: AVCaptureVideoDataOutput?
    ) throws -> AVCaptureSession {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) {
            session.addInput(input)
        }
        if let videoOutput, session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        guard !session.inputs.isEmpty,
              videoOutput == nil || session.outputs.contains(where: { $0 === videoOutput })
        else {
            throw CameraPreviewPanelError.cannotAddInput
        }

        return session
    }

    private static func makePanel(
        frame: NSRect,
        session: AVCaptureSession,
        style: CameraPreviewStyle,
        showsHoverControls: Bool,
        snapOrigin: @escaping (NSRect) -> NSPoint,
        onMove: @escaping (NSRect) -> Void,
        onClose: @escaping @MainActor () -> Void
    ) -> NSPanel {
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
        panel.contentView = CameraPreviewPanelView(
            session: session,
            style: style,
            showsHoverControls: showsHoverControls,
            snapOrigin: snapOrigin,
            onMove: onMove,
            onClose: onClose
        )
        return panel
    }

    private func panelFrame(size: CGSize, preferredDisplayID: DisplayID?) -> NSRect {
        let screen =
            snapRect.flatMap(Self.screen(containing:))
            ?? preferredDisplayID.flatMap(Self.screen(displayID:))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let displayID = screen?.displayID
        let constraintRect = snapRect ?? screen?.visibleFrame ?? .zero
        let size = Self.constrainedPanelSize(size, in: constraintRect)

        if let displayID,
           let origin = panelOriginsByDisplayID[displayID] {
            return NSRect(
                origin: Self.constrainedOrigin(origin, size: size, in: constraintRect),
                size: size
            )
        }

        return NSRect(
            x: constraintRect.maxX - size.width - Self.edgeMargin,
            y: constraintRect.minY + Self.edgeMargin,
            width: size.width,
            height: size.height
        )
    }

    private func constraintRect(for frame: NSRect) -> NSRect {
        snapRect
            ?? Self.screen(containing: frame)?.visibleFrame
            ?? .zero
    }

    private func rememberPanelOrigin() {
        guard let panel else {
            return
        }

        rememberPanelOrigin(frame: panel.frame)
    }

    private func rememberPanelOrigin(frame: NSRect) {
        guard let displayID = Self.screen(containing: frame)?.displayID else {
            return
        }

        panelOriginsByDisplayID[displayID] = frame.origin
        if let placement = try? CameraPreviewPlacement(point: frame.origin) {
            onPlacementChange?(displayID, placement)
        }
    }

    private static func captureDevice(deviceID: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        .devices
        .first { $0.uniqueID == deviceID }
    }

    private static func screen(displayID: DisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    fileprivate static func screen(containing frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    fileprivate static func snappedOrigin(for frame: NSRect, snapRect: NSRect?) -> NSPoint {
        guard let constraintRect = snapRect ?? screen(containing: frame)?.visibleFrame else {
            return frame.origin
        }

        let candidates = cornerOrigins(size: frame.size, in: constraintRect)
        let closest = candidates.min { first, second in
            first.distance(to: frame.origin) < second.distance(to: frame.origin)
        }

        if let closest, closest.distance(to: frame.origin) <= cornerSnapDistance {
            return closest
        }

        return constrainedOrigin(frame.origin, size: frame.size, in: constraintRect)
    }

    private static func cornerOrigins(size: CGSize, in rect: NSRect) -> [NSPoint] {
        return [
            constrainedOrigin(
                NSPoint(x: rect.minX + edgeMargin, y: rect.minY + edgeMargin),
                size: size,
                in: rect
            ),
            constrainedOrigin(
                NSPoint(x: rect.maxX - size.width - edgeMargin, y: rect.minY + edgeMargin),
                size: size,
                in: rect
            ),
            constrainedOrigin(
                NSPoint(x: rect.minX + edgeMargin, y: rect.maxY - size.height - edgeMargin),
                size: size,
                in: rect
            ),
            constrainedOrigin(
                NSPoint(x: rect.maxX - size.width - edgeMargin, y: rect.maxY - size.height - edgeMargin),
                size: size,
                in: rect
            )
        ]
    }

    private static func constrainedOrigin(
        _ origin: NSPoint,
        size: CGSize,
        in rect: NSRect
    ) -> NSPoint {
        let maxX = max(rect.minX, rect.maxX - size.width)
        let maxY = max(rect.minY, rect.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, rect.minX), maxX),
            y: min(max(origin.y, rect.minY), maxY)
        )
    }

    private static func constrainedPanelSize(_ size: CGSize, in rect: NSRect) -> CGSize {
        guard rect.width > 0, rect.height > 0 else {
            return size
        }

        let maxSide = min(rect.width, rect.height)
        let preferredSide = min(size.width, size.height)
        guard preferredSide > maxSide else {
            return size
        }

        let side = max(1, maxSide)
        return CGSize(width: side, height: side)
    }

    private static let edgeMargin: CGFloat = 28
    private static let cornerSnapDistance: CGFloat = 56
    private static let logger = Logger(subsystem: "media.luxel.app", category: "CameraCutout")
}

extension CameraPreviewPanelController {
    func prepareCutout() async throws {
        if portraitMattingProcessor == nil {
            portraitMattingProcessor = portraitMattingProcessorFactory()
        }
        guard let portraitMattingProcessor else {
            throw MODNetPortraitMattingError.missingModel
        }

        try await Task.detached(priority: .userInitiated) {
            try portraitMattingProcessor.prepare()
        }.value
    }

    private func makeCutoutPipeline(style: CameraPreviewStyle) -> CameraCutoutSessionPipeline? {
        guard let portraitMattingProcessor else {
            return nil
        }

        return CameraCutoutSessionPipeline(
            processor: portraitMattingProcessor,
            outputSize: style.size.panelSize,
            isMirrored: style.isMirrored,
            onImage: { [weak self] image in
                Task { @MainActor [weak self] in
                    (self?.panel?.contentView as? CameraPreviewPanelView)?.presentCutout(image)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleCutoutFailure(error)
                }
            }
        )
    }

    private func handleCutoutFailure(_ error: any Error) {
        guard let session, let cutoutPipeline else {
            return
        }

        Self.logger.error(
            "Camera Cutout fell back to Squircle: \(error.localizedDescription, privacy: .public)"
        )
        cutoutPipeline.stop()
        self.cutoutPipeline = nil
        removeCutoutObservers()
        (panel?.contentView as? CameraPreviewPanelView)?.showDirectFallback(session: session)
        onCutoutFailure?()
    }

    private func observeCutoutFailures(session: AVCaptureSession, device: AVCaptureDevice) {
        let center = NotificationCenter.default
        cutoutObserverTokens = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCutoutFailure(CameraPreviewPanelError.sessionInterrupted)
                }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification,
                object: session,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCutoutFailure(CameraPreviewPanelError.sessionInterrupted)
                }
            },
            center.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: device,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleCutoutFailure(CameraPreviewPanelError.deviceDisconnected)
                }
            }
        ]
    }

    private func removeCutoutObservers() {
        let center = NotificationCenter.default
        cutoutObserverTokens.forEach(center.removeObserver)
        cutoutObserverTokens = []
    }
}

private enum CameraPreviewPanelError: Error {
    case cannotAddInput
    case sessionInterrupted
    case deviceDisconnected
}

private struct CameraCaptureSessionHandle: @unchecked Sendable {
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

private final class CameraPreviewPanelView: NSView {
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
    fileprivate func distance(to other: NSPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}

extension CameraPreviewPlacement {
    fileprivate init(point: NSPoint) throws {
        try self.init(x: Double(point.x), y: Double(point.y))
    }

    fileprivate var point: NSPoint {
        NSPoint(x: xPosition, y: yPosition)
    }
}

extension CameraPreviewSize {
    fileprivate var panelSize: CGSize {
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
    fileprivate func cornerRadius(for size: CGSize) -> CGFloat {
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

private extension CameraPreviewStyle {
    func replacingShape(_ shape: CameraOverlayShape) -> CameraPreviewStyle {
        CameraPreviewStyle(shape: shape, size: size, isMirrored: isMirrored)
    }
}

extension NSScreen {
    fileprivate var displayID: DisplayID? {
        guard
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        return DisplayID(screenNumber.uint32Value)
    }
}
