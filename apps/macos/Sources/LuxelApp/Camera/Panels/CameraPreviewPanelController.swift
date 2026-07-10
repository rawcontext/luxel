import AVFoundation
import AppKit
import LuxelCore
import OSLog

@MainActor
final class CameraPreviewPanelController {
    let sessionQueue = DispatchQueue(label: "app.luxel.cameraPreview.session")
    let portraitMattingProcessorFactory: @MainActor () -> MODNetPortraitMattingProcessor?
    var portraitMattingProcessor: MODNetPortraitMattingProcessor?
    var panel: NSPanel?
    var session: AVCaptureSession?
    var cutoutPipeline: CameraCutoutSessionPipeline?
    var cutoutObserverTokens: [NSObjectProtocol] = []
    var onCutoutFailure: (@MainActor () -> Void)?
    var panelOriginsByDisplayID: [DisplayID: NSPoint] = [:]
    var snapRect: NSRect?
    var onPlacementChange: (@MainActor (DisplayID, CameraPreviewPlacement) -> Void)?

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
            try presentPanel(
                device: device,
                presentation: CameraPanelPresentation(
                    style: style,
                    preferredDisplayID: preferredDisplayID,
                    showsHoverControls: showsHoverControls,
                    onClose: onClose
                )
            )
        } catch {
            NSSound.beep()
        }
    }

    private func presentPanel(
        device: AVCaptureDevice,
        presentation: CameraPanelPresentation
    ) throws {
        let requestedCutout = presentation.style.shape.usesPortraitMatting
        let usesCutout = requestedCutout && portraitMattingProcessor?.isPrepared == true
        let style = requestedCutout && !usesCutout
            ? presentation.style.replacingShape(.circle)
            : presentation.style
        let cutoutPipeline = usesCutout ? makeCutoutPipeline(style: style) : nil
        let session = try Self.makeSession(device: device, videoOutput: cutoutPipeline?.videoOutput)
        let frame = panelFrame(size: style.size.panelSize, preferredDisplayID: presentation.preferredDisplayID)
        let panel = Self.makePanel(
            frame: frame,
            session: session,
            style: style,
            showsHoverControls: presentation.showsHoverControls,
            callbacks: CameraPreviewPanelCallbacks(
                snapOrigin: { [weak self] frame in
                    Self.snappedOrigin(for: frame, snapRect: self?.snapRect)
                },
                onMove: { [weak self] frame in self?.rememberPanelOrigin(frame: frame) },
                onClose: presentation.onClose
            )
        )
        panel.orderFrontRegardless()
        finishPresentation(
            panel: panel,
            session: session,
            pipeline: cutoutPipeline,
            device: device,
            requestedCutout: requestedCutout
        )
    }

    private func finishPresentation(
        panel: NSPanel,
        session: AVCaptureSession,
        pipeline: CameraCutoutSessionPipeline?,
        device: AVCaptureDevice,
        requestedCutout: Bool
    ) {
        self.session = session
        self.panel = panel
        cutoutPipeline = pipeline
        rememberPanelOrigin(frame: panel.frame)
        if let pipeline {
            observeCutoutFailures(session: session, device: device)
            pipeline.start()
        } else if requestedCutout {
            onCutoutFailure?()
        }
        let sessionHandle = CameraCaptureSessionHandle(session)
        sessionQueue.async { [sessionHandle] in sessionHandle.session.startRunning() }
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

}
