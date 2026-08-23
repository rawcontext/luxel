import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class OverlayPanelNotchPresenter: NotchPresenter, @unchecked Sendable {
    static let panelSize = NSSize(width: 536, height: 188)
    static let expandedHeight: CGFloat = 52
    private static let collapsedHoverHorizontalOutset: CGFloat = 12
    private static let collapsedHoverHeight: CGFloat = 14
    private static let edgeMargin: CGFloat = 8
    private static let hoverExitDebounceNanoseconds: UInt64 = 180_000_000
    private static let mouseMonitorEventMask: NSEvent.EventTypeMask = [
        .mouseMoved,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown
    ]

    private let exclusionRegistry: CaptureExclusionRegistry
    private let stream: AsyncStream<NotchInteraction>
    private let continuation: AsyncStream<NotchInteraction>.Continuation

    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchSurfaceView>?
    private var currentUpdate: NotchPresentationUpdate?
    private var currentGeometry: NotchGeometry?
    private var exclusionRegistrationID: UUID?
    private var hoverRects: [NSRect] = []
    private var isHovering = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var hoverExitTask: Task<Void, Never>?
    private var morphInTask: Task<Void, Never>?
    private var morphInGeneration = 0
    private var currentPhase: NotchRenderPhase = .settled

    init(exclusionRegistry: CaptureExclusionRegistry) {
        self.exclusionRegistry = exclusionRegistry
        let pair = AsyncStream<NotchInteraction>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
    }

    var interactions: AsyncStream<NotchInteraction> {
        stream
    }

    func acquire(on geometry: NotchGeometry) async {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateHoverRects(for: geometry, isExpanded: false)
        installMouseMonitorsIfNeeded()
        panel.setFrame(Self.panelFrame(for: geometry), display: true)
        handleMouseLocation(NSEvent.mouseLocation)
        await registerForCaptureExclusion(panel)
    }

    func present(_ update: NotchPresentationUpdate) async {
        let previousUpdate = currentUpdate
        currentUpdate = update

        let panel = panel ?? makePanel()
        self.panel = panel
        updateHoverRects(for: update.geometry, isExpanded: update.presentationState == .expanded)
        installMouseMonitorsIfNeeded()
        panel.setFrame(Self.panelFrame(for: update.geometry), display: true)
        panel.ignoresMouseEvents = update.activity == .dormant
        let shouldMorphIn =
            !update.motion.reducesMotion && update.activity != .dormant
            && update.presentationState == .expanded
            && (previousUpdate?.presentationState != .expanded || !panel.isVisible)

        if update.activity == .dormant {
            cancelMorphIn()
            render(update, in: panel)
            panel.orderOut(nil)
        } else {
            if update.presentationState != .expanded {
                cancelMorphIn()
            }

            render(update, phase: shouldMorphIn ? .seed : activePhase, in: panel)

            if !panel.isVisible {
                panel.orderFrontRegardless()
            }

            if shouldMorphIn {
                morphInGeneration += 1
                let generation = morphInGeneration
                morphInTask?.cancel()
                morphInTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 16_000_000)
                    guard !Task.isCancelled,
                        self?.morphInGeneration == generation,
                        let panel = self?.panel,
                        let update = self?.currentUpdate
                    else {
                        return
                    }

                    self?.render(update, phase: .settled, in: panel)
                    self?.morphInTask = nil
                }
            }
        }

        await registerForCaptureExclusion(panel)
        handleMouseLocation(NSEvent.mouseLocation)
    }

    func setExpanded(_ isExpanded: Bool) async {
        guard let currentUpdate else {
            return
        }

        let update = NotchPresentationUpdate(
            geometry: currentUpdate.geometry,
            activity: currentUpdate.activity,
            presentationState: isExpanded ? .expanded : .collapsed,
            viewModel: currentUpdate.viewModel,
            motion: currentUpdate.motion
        )
        self.currentUpdate = update

        if let panel {
            updateHoverRects(for: update.geometry, isExpanded: isExpanded)
            render(update, phase: .settled, in: panel)
            handleMouseLocation(NSEvent.mouseLocation)
        }
    }

    func release() async {
        panel?.orderOut(nil)
        cancelMorphIn()
        cancelPendingHoverExit()
        removeMouseMonitors()
        hoverRects = []
        isHovering = false
        hostingView = nil
        currentUpdate = nil
        currentGeometry = nil

        if let exclusionRegistrationID {
            await exclusionRegistry.unregister(exclusionRegistrationID)
            self.exclusionRegistrationID = nil
        }
    }

    private var activePhase: NotchRenderPhase {
        morphInTask == nil ? .settled : currentPhase
    }

    private func cancelMorphIn() {
        morphInGeneration += 1
        morphInTask?.cancel()
        morphInTask = nil
        currentPhase = .settled
    }

    private func makePanel() -> NSPanel {
        let panel = NotchOverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func render(
        _ update: NotchPresentationUpdate,
        phase: NotchRenderPhase = .settled,
        in panel: NSPanel
    ) {
        currentPhase = phase
        let rootView = NotchSurfaceView(
            update: update,
            phase: phase,
            onAction: { [weak self] actionID in
                self?.continuation.yield(.action(actionID))
            },
            onDragArtifact: { [weak self] artifact in
                self?.continuation.yield(.dragArtifact(artifact))
            }
        )

        if let hostingView {
            withAnimation(rootView.animation) {
                hostingView.rootView = rootView
            }
            return
        }

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        self.hostingView = hostingView
    }

    private func registerForCaptureExclusion(_ panel: NSPanel) async {
        guard panel.windowNumber > 0 else {
            return
        }

        let windowID = UInt32(panel.windowNumber)
        if let exclusionRegistrationID {
            await exclusionRegistry.register(windowID: windowID, registrationID: exclusionRegistrationID)
        } else {
            exclusionRegistrationID = await exclusionRegistry.register(windowID: windowID)
        }
    }

}

extension OverlayPanelNotchPresenter {
    private func installMouseMonitorsIfNeeded() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: Self.mouseMonitorEventMask
        ) { [weak self] event in
            let isMouseDown = event.isMouseDown
            Task { @MainActor in
                self?.handleMouseEvent(isMouseDown: isMouseDown)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: Self.mouseMonitorEventMask
        ) { [weak self] event in
            let isMouseDown = event.isMouseDown
            Task { @MainActor in
                self?.handleMouseEvent(isMouseDown: isMouseDown)
            }
        }
    }

    private func removeMouseMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }

        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handleMouseLocation(_ location: NSPoint) {
        guard !hoverRects.isEmpty else {
            return
        }

        let hovering = hoverRects.contains { $0.contains(location) }
        if hovering {
            cancelPendingHoverExit()
            guard !isHovering else {
                return
            }

            if let currentGeometry {
                hoverRects = Self.hoverRects(for: currentGeometry, isExpanded: true)
            }
            isHovering = true
            continuation.yield(.hoverEntered)
            return
        }

        guard isHovering else {
            return
        }

        scheduleHoverExit()
    }

    private func scheduleHoverExit() {
        guard hoverExitTask == nil else {
            return
        }

        hoverExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.hoverExitDebounceNanoseconds)
            } catch {
                return
            }

            self?.completePendingHoverExit()
        }
    }

    private func completePendingHoverExit() {
        hoverExitTask = nil
        guard isHovering,
            !hoverRects.contains(where: { $0.contains(NSEvent.mouseLocation) })
        else {
            return
        }

        if let currentGeometry {
            hoverRects = Self.hoverRects(for: currentGeometry, isExpanded: false)
        }
        isHovering = false
        continuation.yield(.hoverExited)
    }

    private func handleMouseEvent(isMouseDown: Bool) {
        if isMouseDown {
            collapseExpandedNotchIfNeeded(at: NSEvent.mouseLocation)
            return
        }

        handleMouseLocation(NSEvent.mouseLocation)
    }

    private func collapseExpandedNotchIfNeeded(at location: NSPoint) {
        guard currentUpdate?.presentationState == .expanded,
            let currentGeometry,
            !Self.expandedSurfaceHitRect(for: currentGeometry).contains(location)
        else {
            return
        }

        cancelPendingHoverExit()
        isHovering = false
        hoverRects = Self.hoverRects(for: currentGeometry, isExpanded: false)
        continuation.yield(.setExpanded(false))
    }

    private func cancelPendingHoverExit() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
    }

    private func updateHoverRects(for geometry: NotchGeometry, isExpanded: Bool) {
        currentGeometry = geometry
        hoverRects = Self.hoverRects(for: geometry, isExpanded: isExpanded)
    }

    private static func panelFrame(for geometry: NotchGeometry) -> NSRect {
        let screen = geometry.screenFrame.nsRect
        let housing = geometry.cameraHousingRect.nsRect
        let minX = screen.minX + edgeMargin
        let maxX = max(minX, screen.maxX - panelSize.width - edgeMargin)
        let originX = min(max(housing.midX - panelSize.width / 2, minX), maxX)
        let originY = screen.maxY - panelSize.height
        return NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize)
    }

    private static func hoverRects(for geometry: NotchGeometry, isExpanded: Bool) -> [NSRect] {
        if isExpanded {
            return [expandedSurfaceHitRect(for: geometry)]
        }

        return [collapsedHoverRect(for: geometry)]
    }

    private static func collapsedHoverRect(for geometry: NotchGeometry) -> NSRect {
        let housing = geometry.cameraHousingRect.nsRect
        let height = min(collapsedHoverHeight, housing.height)
        return NSRect(
            x: housing.minX - collapsedHoverHorizontalOutset,
            y: housing.maxY - height,
            width: housing.width + collapsedHoverHorizontalOutset * 2,
            height: height
        )
    }

    private static func expandedSurfaceHitRect(for geometry: NotchGeometry) -> NSRect {
        let screen = geometry.screenFrame.nsRect
        let housing = geometry.cameraHousingRect.nsRect
        let width = notchWidth(for: geometry)
        return NSRect(
            x: housing.midX - width / 2,
            y: screen.maxY - expandedHeight,
            width: width,
            height: expandedHeight
        )
        .insetBy(dx: -8, dy: -8)
    }

    static func notchWidth(for geometry: NotchGeometry) -> CGFloat {
        max(170, min(220, geometry.cameraHousingRect.nsRect.width))
    }
}
