import AVFoundation
import AppKit
import LuxelCore
import OSLog

extension CameraPreviewPanelController {
    static func makeSession(
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

    static func makePanel(
        frame: NSRect,
        session: AVCaptureSession,
        style: CameraPreviewStyle,
        showsHoverControls: Bool,
        callbacks: CameraPreviewPanelCallbacks
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
            snapOrigin: callbacks.snapOrigin,
            onMove: callbacks.onMove,
            onClose: callbacks.onClose
        )
        return panel
    }

    func panelFrame(size: CGSize, preferredDisplayID: DisplayID?) -> NSRect {
        let screen =
            snapRect.flatMap(Self.screen(containing:))
            ?? preferredDisplayID.flatMap(Self.screen(displayID:))
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let displayID = screen?.displayID
        let constraintRect = snapRect ?? screen?.visibleFrame ?? .zero
        let size = Self.constrainedPanelSize(size, in: constraintRect)

        if let displayID,
            let origin = panelOriginsByDisplayID[displayID]
        {
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

    func constraintRect(for frame: NSRect) -> NSRect {
        snapRect
            ?? Self.screen(containing: frame)?.visibleFrame
            ?? .zero
    }

    func rememberPanelOrigin() {
        guard let panel else {
            return
        }

        rememberPanelOrigin(frame: panel.frame)
    }

    func rememberPanelOrigin(frame: NSRect) {
        guard let displayID = Self.screen(containing: frame)?.displayID else {
            return
        }

        panelOriginsByDisplayID[displayID] = frame.origin
        if let placement = try? CameraPreviewPlacement(point: frame.origin) {
            onPlacementChange?(displayID, placement)
        }
    }

    static func captureDevice(deviceID: String) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        .devices
        .first { $0.uniqueID == deviceID }
    }

    static func screen(displayID: DisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == displayID }
    }

    static func screen(containing frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    static func snappedOrigin(for frame: NSRect, snapRect: NSRect?) -> NSPoint {
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

    static func cornerOrigins(size: CGSize, in rect: NSRect) -> [NSPoint] {
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
                NSPoint(
                    x: rect.maxX - size.width - edgeMargin, y: rect.maxY - size.height - edgeMargin),
                size: size,
                in: rect
            )
        ]
    }

    static func constrainedOrigin(
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

    static func constrainedPanelSize(_ size: CGSize, in rect: NSRect) -> CGSize {
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

    static let edgeMargin: CGFloat = 28
    static let cornerSnapDistance: CGFloat = 56
    static let logger = Logger(subsystem: "com.rawcontext.luxel", category: "CameraCutout")
}

struct CameraPanelPresentation {
    let style: CameraPreviewStyle
    let preferredDisplayID: DisplayID?
    let showsHoverControls: Bool
    let onClose: @MainActor () -> Void
}

struct CameraPreviewPanelCallbacks {
    let snapOrigin: (NSRect) -> NSPoint
    let onMove: (NSRect) -> Void
    let onClose: @MainActor () -> Void
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

    func makeBackgroundEffectPipeline(
        style: CameraPreviewStyle
    ) -> CameraBackgroundEffectSessionPipeline? {
        if style.backgroundEffect.usesPortraitMatting, portraitMattingProcessor == nil {
            return nil
        }

        let telemetry = CameraBackgroundEffectTelemetry(effect: style.backgroundEffect)
        return CameraBackgroundEffectSessionPipeline(
            effect: style.backgroundEffect,
            processor: portraitMattingProcessor,
            telemetry: telemetry,
            outputSize: style.size.panelSize,
            isMirrored: style.isMirrored,
            onFrame: { [weak self] frame in
                Task { @MainActor [weak self] in
                    (self?.panel?.contentView as? CameraPreviewPanelView)?.presentCutout(frame)
                    telemetry.recordPresentation(sourceTimestamp: frame.sourceTimestamp)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.handleCutoutFailure(error)
                }
            }
        )
    }

    func handleCutoutFailure(_ error: any Error) {
        guard let session, let backgroundEffectPipeline else {
            return
        }

        Self.logger.error(
            "Camera background effect fell back to direct preview: \(error.localizedDescription, privacy: .public)"
        )
        backgroundEffectPipeline.stop()
        self.backgroundEffectPipeline = nil
        removeCutoutObservers()
        (panel?.contentView as? CameraPreviewPanelView)?.showDirectFallback(session: session)
        onCutoutFailure?()
    }

    func observeCutoutFailures(session: AVCaptureSession, device: AVCaptureDevice) {
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

    func removeCutoutObservers() {
        let center = NotificationCenter.default
        cutoutObserverTokens.forEach(center.removeObserver)
        cutoutObserverTokens = []
    }
}
