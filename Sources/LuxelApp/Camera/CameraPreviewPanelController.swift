import AppKit
import AVFoundation
import LuxelCore

@MainActor
final class CameraPreviewPanelController {
    private let sessionQueue = DispatchQueue(label: "app.luxel.cameraPreview.session")
    private var panel: NSPanel?
    private var session: AVCaptureSession?
    private var panelOrigin: NSPoint?

    func present(deviceID: String, style: CameraPreviewStyle) {
        let origin = panel?.frame.origin ?? panelOrigin
        close()

        guard let device = Self.captureDevice(deviceID: deviceID) else {
            NSSound.beep()
            return
        }

        do {
            let session = try Self.makeSession(device: device)
            let frame = Self.panelFrame(size: style.size.panelSize, preserving: origin)
            let panel = Self.makePanel(frame: frame, session: session, style: style)
            panel.orderFrontRegardless()

            self.session = session
            self.panel = panel
            self.panelOrigin = panel.frame.origin

            let sessionHandle = CameraCaptureSessionHandle(session)
            sessionQueue.async { [sessionHandle] in
                sessionHandle.session.startRunning()
            }
        } catch {
            NSSound.beep()
        }
    }

    func close() {
        panelOrigin = panel?.frame.origin ?? panelOrigin
        panel?.close()
        panel = nil

        guard let session else {
            return
        }

        self.session = nil
        let sessionHandle = CameraCaptureSessionHandle(session)
        sessionQueue.async { [sessionHandle] in
            if sessionHandle.session.isRunning {
                sessionHandle.session.stopRunning()
            }
        }
    }

    private static func makeSession(device: AVCaptureDevice) throws -> AVCaptureSession {
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)

        session.beginConfiguration()
        session.sessionPreset = .medium
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()

        guard !session.inputs.isEmpty else {
            throw CameraPreviewPanelError.cannotAddInput
        }

        return session
    }

    private static func makePanel(
        frame: NSRect,
        session: AVCaptureSession,
        style: CameraPreviewStyle
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
        panel.contentView = CameraPreviewPanelView(session: session, style: style)
        return panel
    }

    private static func panelFrame(size: CGSize, preserving origin: NSPoint?) -> NSRect {
        if let origin {
            return NSRect(origin: origin, size: size)
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let margin: CGFloat = 28
        return NSRect(
            x: visibleFrame.maxX - size.width - margin,
            y: visibleFrame.minY + margin,
            width: size.width,
            height: size.height
        )
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
}

private enum CameraPreviewPanelError: Error {
    case cannotAddInput
}

private struct CameraCaptureSessionHandle: @unchecked Sendable {
    let session: AVCaptureSession

    init(_ session: AVCaptureSession) {
        self.session = session
    }
}

private final class CameraPreviewPanelView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let style: CameraPreviewStyle
    private var dragStartPoint: NSPoint?
    private var dragStartFrame: NSRect?

    init(session: AVCaptureSession, style: CameraPreviewStyle) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.transform = style.isMirrored ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
        layer?.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        layer?.cornerRadius = style.shape.cornerRadius(for: bounds.size)
        layer?.masksToBounds = true
    }

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = window?.convertPoint(toScreen: event.locationInWindow)
        dragStartFrame = window?.frame
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let dragStartPoint,
              let dragStartFrame else {
            return
        }

        let point = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(
            x: point.x - dragStartPoint.x,
            y: point.y - dragStartPoint.y
        )
        window.setFrameOrigin(NSPoint(
            x: dragStartFrame.origin.x + delta.x,
            y: dragStartFrame.origin.y + delta.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        dragStartFrame = nil
    }
}

private extension CameraPreviewSize {
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

private extension CameraOverlayShape {
    func cornerRadius(for size: CGSize) -> CGFloat {
        switch self {
        case .circle:
            min(size.width, size.height) / 2
        case .roundedRect:
            16
        }
    }
}
