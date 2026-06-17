import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class OverlayPanelNotchPresenter: NotchPresenter, @unchecked Sendable {
    fileprivate static let panelSize = NSSize(width: 536, height: 188)
    fileprivate static let expandedHeight: CGFloat = 58
    private static let edgeMargin: CGFloat = 8

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
        let shouldMorphIn = !update.motion.reducesMotion &&
            update.activity != .dormant &&
            update.presentationState == .expanded &&
            (
                previousUpdate?.presentationState != .expanded ||
                !panel.isVisible
            )

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
                          let update = self?.currentUpdate else {
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

    private func installMouseMonitorsIfNeeded() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else {
            return
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseLocation(NSEvent.mouseLocation)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in
                self?.handleMouseLocation(NSEvent.mouseLocation)
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
        guard hovering != isHovering else {
            return
        }

        if let currentGeometry {
            hoverRects = Self.hoverRects(for: currentGeometry, isExpanded: hovering)
        }
        isHovering = hovering
        continuation.yield(hovering ? .hoverEntered : .hoverExited)
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
            return [
                geometry.cameraHousingRect.nsRect,
                expandedSurfaceRect(for: geometry)
            ]
        }

        return [geometry.cameraHousingRect.nsRect]
    }

    private static func expandedSurfaceRect(for geometry: NotchGeometry) -> NSRect {
        let screen = geometry.screenFrame.nsRect
        let housing = geometry.cameraHousingRect.nsRect
        let width = notchWidth(for: geometry)
        let originX = housing.midX - width / 2
        return NSRect(
            x: originX,
            y: screen.maxY - expandedHeight,
            width: width,
            height: expandedHeight
        )
    }

    fileprivate static func notchWidth(for geometry: NotchGeometry) -> CGFloat {
        max(170, min(220, geometry.cameraHousingRect.nsRect.width))
    }
}

private final class NotchOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

private enum NotchRenderPhase: Equatable {
    case seed
    case settled
}

private struct FlatTopIslandShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
        return path
    }
}

private struct NotchSurfaceView: View {
    private static let appleNotchCornerRadius: CGFloat = 8
    private static let pureBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)

    let update: NotchPresentationUpdate
    let phase: NotchRenderPhase
    let onAction: @MainActor (NotchActivityActionID) -> Void
    let onDragArtifact: @MainActor (NotchArtifact) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if update.activity != .dormant {
                islandSurface
                    .offset(y: -50)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(width: OverlayPanelNotchPresenter.panelSize.width, height: OverlayPanelNotchPresenter.panelSize.height)
        .ignoresSafeArea(.all)
        .animation(shellAnimation, value: phase)
        .animation(animation, value: update.presentationState)
        .animation(animation, value: update.activity)
        .accessibilityLabel(update.viewModel.accessibilityLabel)
    }

    fileprivate var animation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .spring(
            response: update.motion.morphSpring.response,
            dampingFraction: update.motion.morphSpring.dampingRatio
        )
    }

    private var shellAnimation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .timingCurve(0.16, 0.92, 0.24, 1, duration: min(update.motion.geometryMorphDuration, 0.22))
    }

    private var contentAnimation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .easeOut(duration: update.motion.contentFadeDuration)
    }

    private var islandSurface: some View {
        expandedSurface
        .padding(.top, 2)
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private var expandedSurface: some View {
        ZStack(alignment: .topLeading) {
            FlatTopIslandShape(cornerRadius: expandedCornerRadius)
                .fill(Self.pureBlack)
                .overlay {
                    FlatTopIslandShape(cornerRadius: expandedCornerRadius)
                        .stroke(.white.opacity(phase == .seed ? 0 : 0.08), lineWidth: 0.8)
                }

            actionRow(buttonSize: 28, iconSize: 12, spacing: 5)
                .offset(y: 6)
                .frame(width: expandedWidth, height: expandedHeight, alignment: .center)
                .opacity(update.viewModel.actions.isEmpty ? 0 : 1)
            .opacity(phase == .settled ? 1 : 0)
            .scaleEffect(phase == .seed ? 0.92 : 1, anchor: .top)
            .animation(contentAnimation, value: phase)
        }
        .frame(width: expandedWidth, height: expandedHeight, alignment: .topLeading)
        .scaleEffect(
            x: phase == .seed ? seedWidth / expandedWidth : 1,
            y: phase == .seed ? seedHeight / expandedHeight : 1,
            anchor: .top
        )
    }

    private func actionRow(
        buttonSize: CGFloat = 34,
        iconSize: CGFloat = 14,
        spacing: CGFloat = 9
    ) -> some View {
        HStack(spacing: spacing) {
            ForEach(update.viewModel.actions, id: \.id) { action in
                Button {
                    onAction(action.id)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .labelStyle(.iconOnly)
                        .font(.system(size: iconSize, weight: .semibold))
                        .frame(width: buttonSize, height: buttonSize)
                        .foregroundStyle(actionForeground(action))
                        .background(actionBackground(action), in: Circle())
                }
                .buttonStyle(.plain)
                .help(action.title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    private func actionForeground(_ action: NotchActivityActionDescriptor) -> Color {
        switch action.role {
        case .destructive:
            .red
        case .primary:
            .black
        case .standard:
            .white
        }
    }

    private func actionBackground(_ action: NotchActivityActionDescriptor) -> Color {
        switch action.role {
        case .destructive:
            .red.opacity(0.16)
        case .primary:
            .white
        case .standard:
            .white.opacity(0.12)
        }
    }

    private var expandedWidth: CGFloat {
        notchWidth
    }

    private var expandedHeight: CGFloat {
        OverlayPanelNotchPresenter.expandedHeight
    }

    private var seedWidth: CGFloat {
        notchWidth
    }

    private var seedHeight: CGFloat {
        34
    }

    private var expandedCornerRadius: CGFloat {
        Self.appleNotchCornerRadius
    }

    private var notchWidth: CGFloat {
        OverlayPanelNotchPresenter.notchWidth(for: update.geometry)
    }
}

private extension NotchScreenRect {
    var nsRect: NSRect {
        NSRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
    }
}
