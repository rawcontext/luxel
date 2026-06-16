import AppKit
import Carbon
import LuxelCore
import LuxelPresentation
import OSLog
import SwiftUI

@MainActor
final class LuxelStatusItemController: NSObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "media.luxel.app",
        category: "StatusItem"
    )

    private let model: LuxelMenuModel
    private let editorModel: LuxelEditorModel
    private let cropperPanelController: LuxelCropperPanelController
    private let shortcutController: LuxelShortcutController
    private let windowPresenter: LuxelWindowPresenter
    private let quickExportProgressPanelController = QuickExportProgressPanelController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var statusRefreshTimer: Timer?
    private var recordingAnimationTimer: Timer?
    private var recordingFrameIndex = 0
    private var currentImageKey: String?
    private var currentStatusItemLength = NSStatusItem.squareLength
    private var isHandlingStatusItemStop = false
    private var statusItemStopTask: Task<Void, Never>?
    private var statusItemStopWatchdogTask: Task<Void, Never>?
    private var recordingAudioLevelTask: Task<Void, Never>?
    private var recordingAudioLevelTaskID: String?
    private var applicationResignActiveObserver: NSObjectProtocol?
    private var menuPanel: NSPanel?
    private var menuHostingController: NSHostingController<AnyView>?
    private var menuPanelContentView: LuxelMenuPanelContentView?
    private var pendingPopoverOpenTask: Task<Void, Never>?
    private var suppressNextPopoverOpenUntil: Date?
    private var activationSourceApplication: NSRunningApplication?

    private let iconSize = NSSize(width: 18, height: 18)
    private let activeIconHeight: CGFloat = 24
    private let activeIconMinWidth: CGFloat = 118
    private let menuPanelWidth: CGFloat = 324
    private let menuPanelFallbackHeight: CGFloat = 260
    private let menuPanelMinimumHeight: CGFloat = 150
    private let menuPanelFittingHeightPadding: CGFloat = 8
    private let menuPanelArrowHeight: CGFloat = 10
    private let statusItemStopWatchdogDelay: Duration = .seconds(8)

    init(
        model: LuxelMenuModel,
        editorModel: LuxelEditorModel,
        cropperPanelController: LuxelCropperPanelController,
        shortcutController: LuxelShortcutController,
        windowPresenter: LuxelWindowPresenter
    ) {
        self.model = model
        self.editorModel = editorModel
        self.cropperPanelController = cropperPanelController
        self.shortcutController = shortcutController
        self.windowPresenter = windowPresenter
        super.init()

        configureStatusItem()
        configurePopover()
        installPopoverDismissalObserver()
        installURLHandler()
        startStatusRefresh()
        refreshStatusItem()
        recoverInterruptedRecording()
    }

    private func configureStatusItem() {
        statusItem.autosaveName = NSStatusItem.AutosaveName("media.luxel.app.statusItem")

        guard let button = statusItem.button else {
            return
        }

        configureStatusItemButton(button)
    }

    private func configureStatusItemButton(_ button: NSStatusBarButton) {
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.sendAction(on: [.leftMouseDown])
        Self.logger.debug("Status item button configured")
    }

    private func configurePopover() {
        let hostingController = NSHostingController(
            rootView: makeMenuRootView()
        )
        hostingController.view.frame = NSRect(origin: .zero, size: fallbackMenuPanelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        menuHostingController = hostingController
    }

    private func makeMenuRootView(arrowCenterX: CGFloat? = nil) -> AnyView {
        AnyView(
            LuxelMenuPanelChrome(
                arrowCenterX: arrowCenterX ?? menuPanelWidth / 2,
                arrowHeight: menuPanelArrowHeight
            ) {
                LuxelMenu(
                    model: model,
                    editorModel: editorModel,
                    cropperPanelController: cropperPanelController,
                    shortcutController: shortcutController,
                    dismissMenu: { [weak self] in
                        self?.closePopover()
                    },
                    openEditorWindow: { [weak self] in
                        self?.openEditorFromPopover()
                    },
                    openSettingsWindow: { [weak self] in
                        self?.openSettingsFromPopover()
                    }
                )
            }
        )
    }

    private func installPopoverDismissalObserver() {
        applicationResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopoverAfterAppDeactivation()
            }
        }
    }

    private func closePopoverAfterAppDeactivation() {
        guard isPopoverShown else {
            return
        }

        if isMouseOverStatusItemButton {
            suppressNextPopoverOpenUntil = Date().addingTimeInterval(0.35)
        }

        closePopover()
    }

    private func recoverInterruptedRecording() {
        Task { @MainActor [weak self] in
            guard let self,
                  let recording = await model.recoverInterruptedRecording() else {
                return
            }

            windowPresenter.openEditor(fileURL: recording.fileURL)
        }
    }

    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    private func startStatusRefresh() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusRefreshTimer = timer
    }

    private func refreshStatusItem() {
        refreshRecordingAudioLevelMonitoring()

        let presentation = model.menuBarStatusPresentation()
        statusItem.button?.toolTip = presentation.accessibilityLabel
        statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)

        if presentation.animatesMenuBarSystemImage {
            setStatusItemLength(activeStatusItemWidth(elapsedText: presentation.menuBarTitle))
            startRecordingAnimation()
        } else if presentation.menuBarSystemImage.isEmpty {
            setStatusItemLength(countdownStatusItemWidth(countdownText: presentation.menuBarTitle))
            stopRecordingAnimation()
            setButtonImage(
                countdownTextImage(
                    text: presentation.menuBarTitle,
                    accessibilityLabel: presentation.accessibilityLabel
                ),
                key: "countdown-\(presentation.menuBarTitle)"
            )
        } else {
            setStatusItemLength(NSStatusItem.squareLength)
            stopRecordingAnimation()
            setButtonImage(
                symbolImage(
                    named: presentation.menuBarSystemImage,
                    accessibilityLabel: presentation.accessibilityLabel
                ),
                key: presentation.menuBarSystemImage
            )
        }

        quickExportProgressPanelController.update(progress: model.quickExportProgress) { [weak model] in
            model?.cancelQuickExport()
        }
    }

    private func setStatusItemLength(_ length: CGFloat) {
        guard currentStatusItemLength != length else {
            return
        }

        statusItem.length = length
        currentStatusItemLength = length
        currentImageKey = nil
        if let button = statusItem.button {
            configureStatusItemButton(button)
        }
    }

    private func refreshRecordingAudioLevelMonitoring() {
        guard let activeRecording = model.recordingState.activeRecording,
              activeRecording.options.audio.capturesMicrophone else {
            stopRecordingAudioLevelMonitoring()
            return
        }

        let taskID = [
            model.recordingAudioLevelMonitorTaskID,
            activeRecording.fileURL.path,
            activeRecording.options.audio.microphoneDeviceID ?? AudioInputDeviceID.systemDefault,
        ].joined(separator: ":")
        guard recordingAudioLevelTaskID != taskID else {
            return
        }

        stopRecordingAudioLevelMonitoring()
        recordingAudioLevelTaskID = taskID
        recordingAudioLevelTask = Task { @MainActor [weak model] in
            await model?.watchAudioLevels(onlyWhenRecording: true)
        }
    }

    private func stopRecordingAudioLevelMonitoring() {
        guard recordingAudioLevelTask != nil || recordingAudioLevelTaskID != nil else {
            return
        }

        recordingAudioLevelTask?.cancel()
        recordingAudioLevelTask = nil
        recordingAudioLevelTaskID = nil
        model.audioLevelSample = .silent
    }

    @objc private func handleStatusItemClick() {
        Self.logger.info(
            """
            Status item clicked has_active_recording=\(self.model.hasActiveRecording, privacy: .public) \
            recording_state=\(self.model.recordingState.loggingDescription, privacy: .public) \
            is_handling_stop=\(self.isHandlingStatusItemStop, privacy: .public) \
            button_configured=\(self.isStatusItemButtonConfigured, privacy: .public) \
            popover_shown=\(self.isPopoverShown, privacy: .public)
            """
        )

        if model.hasActiveRecording {
            stopRecordingFromStatusItem()
            return
        }

        rememberActivationSourceApplication()
        togglePopover()
    }

    private func rememberActivationSourceApplication() {
        guard let frontmostApplication = NSWorkspace.shared.frontmostApplication,
              frontmostApplication.processIdentifier != NSRunningApplication.current.processIdentifier else {
            return
        }

        activationSourceApplication = frontmostApplication
    }

    private func openEditorFromPopover() {
        windowPresenter.openEditor(activationSource: activationSourceApplication)
    }

    private func openSettingsFromPopover() {
        windowPresenter.openSettings(activationSource: activationSourceApplication)
    }

    private var isStatusItemButtonConfigured: Bool {
        guard let button = statusItem.button else {
            return false
        }

        return button.target === self && button.action == #selector(handleStatusItemClick)
    }

    private func togglePopover() {
        guard statusItem.button != nil else {
            return
        }

        if isPopoverShown {
            closePopover()
        } else if shouldSuppressPopoverOpenAfterRecentDismissal {
            suppressNextPopoverOpenUntil = nil
        } else {
            openPopover()
        }
    }

    private var isPopoverShown: Bool {
        menuPanel?.isVisible == true
    }

    private var shouldSuppressPopoverOpenAfterRecentDismissal: Bool {
        guard let suppressNextPopoverOpenUntil else {
            return false
        }

        if suppressNextPopoverOpenUntil > Date() {
            return true
        }

        self.suppressNextPopoverOpenUntil = nil
        return false
    }

    private var isMouseOverStatusItemButton: Bool {
        guard let button = statusItem.button,
              let window = button.window else {
            return false
        }

        let buttonFrame = window
            .convertToScreen(button.convert(button.bounds, to: nil))
            .insetBy(dx: -4, dy: -4)
        return buttonFrame.contains(NSEvent.mouseLocation)
    }

    private func openPopover() {
        pendingPopoverOpenTask?.cancel()
        pendingPopoverOpenTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await prepareMenuForPopover()

            guard !Task.isCancelled,
                  let button = statusItem.button else {
                pendingPopoverOpenTask = nil
                return
            }

            showPopover(relativeTo: button)
            pendingPopoverOpenTask = nil
        }
    }

    private func prepareMenuForPopover() async {
        model.refreshRecentRecordings()
        await model.refreshPermissions()
        await model.refreshCaptureTargets()
        await Task.yield()
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        model.refreshRecentRecordings()
        menuHostingController?.rootView = makeMenuRootView(
            arrowCenterX: menuPanelContentView?.arrowCenterX ?? menuPanelWidth / 2
        )

        let panel = menuPanel ?? makeMenuPanel()
        menuPanel = panel

        updateMenuPanelFrame(panel, relativeTo: button, display: false)
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self,
                  let panel,
                  panel.isVisible,
                  let button = self.statusItem.button else {
                return
            }

            self.updateMenuPanelFrame(panel, relativeTo: button, display: true)
        }
    }

    private func updateMenuPanelFrame(
        _ panel: NSPanel,
        relativeTo button: NSStatusBarButton,
        display: Bool
    ) {
        layoutStatusItemButton(button)

        let panelSize = fittedMenuPanelSize()
        let placement = menuPanelPlacement(relativeTo: button, panelSize: panelSize)
        menuPanelContentView?.arrowCenterX = placement.arrowCenterX
        menuHostingController?.rootView = makeMenuRootView(arrowCenterX: placement.arrowCenterX)
        panel.setFrame(placement.frame, display: display)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    private func layoutStatusItemButton(_ button: NSStatusBarButton) {
        button.window?.contentView?.layoutSubtreeIfNeeded()
        button.superview?.layoutSubtreeIfNeeded()
        button.layoutSubtreeIfNeeded()
    }

    private func closePopover() {
        pendingPopoverOpenTask?.cancel()
        pendingPopoverOpenTask = nil
        menuPanel?.orderOut(nil)
    }

    private var fallbackMenuPanelSize: NSSize {
        NSSize(width: menuPanelWidth, height: menuPanelFallbackHeight)
    }

    private func fittedMenuPanelSize() -> NSSize {
        guard let menuHostingController else {
            return fallbackMenuPanelSize
        }

        let fittingSize = menuHostingController.sizeThatFits(in: CGSize(
            width: menuPanelWidth,
            height: CGFloat.greatestFiniteMagnitude
        ))
        let fittedHeight = fittingSize.height.isFinite && fittingSize.height > 0
            ? fittingSize.height
            : menuPanelFallbackHeight
        let height = ceil(max(menuPanelMinimumHeight, fittedHeight + menuPanelFittingHeightPadding))

        return NSSize(width: menuPanelWidth, height: height)
    }

    private func makeMenuPanel() -> NSPanel {
        let panel = LuxelMenuPanel(
            contentRect: NSRect(origin: .zero, size: fallbackMenuPanelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.contentView = makeMenuPanelContentView()
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .popUpMenu
        return panel
    }

    private func makeMenuPanelContentView() -> NSView {
        let container = LuxelMenuPanelContentView(
            frame: NSRect(origin: .zero, size: fallbackMenuPanelSize),
            arrowHeight: menuPanelArrowHeight
        )
        menuPanelContentView = container

        if let hostingView = menuHostingController?.view {
            hostingView.frame = container.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            container.addSubview(hostingView)
        }

        return container
    }

    private func menuPanelPlacement(
        relativeTo button: NSStatusBarButton,
        panelSize: NSSize
    ) -> (frame: NSRect, arrowCenterX: CGFloat) {
        let buttonFrame = button.window.map { window in
            window.convertToScreen(button.convert(button.bounds, to: nil))
        } ?? .zero
        let screenFrame = button.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let margin: CGFloat = 8
        let x = min(
            max(buttonFrame.midX - panelSize.width / 2, screenFrame.minX + margin),
            screenFrame.maxX - panelSize.width - margin
        )
        let topY = buttonFrame.minY > 0 ? buttonFrame.minY : screenFrame.maxY
        let y = topY - panelSize.height
        let frame = NSRect(origin: NSPoint(x: x, y: y), size: panelSize)
        let arrowCenterX = buttonFrame.midX - frame.minX

        return (frame, arrowCenterX)
    }

    private func stopRecordingFromStatusItem() {
        guard !isHandlingStatusItemStop else {
            Self.logger.info(
                """
                Status item stop ignored reason=stop-already-handling \
                recording_state=\(self.model.recordingState.loggingDescription, privacy: .public)
                """
            )
            return
        }

        isHandlingStatusItemStop = true
        closePopover()
        Self.logger.info(
            """
            Status item stop began recording_state=\(self.model.recordingState.loggingDescription, privacy: .public) \
            active_recording=\(self.model.recordingState.activeRecording?.name ?? "none", privacy: .private)
            """
        )

        statusItemStopTask?.cancel()
        statusItemStopWatchdogTask?.cancel()

        statusItemStopTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            Self.logger.info(
                "Status item stop task started recording_state=\(self.model.recordingState.loggingDescription, privacy: .public)"
            )
            let stopAction = await model.stopRecording()
            guard !Task.isCancelled else {
                Self.logger.info("Status item stop task cancelled after stop returned")
                return
            }

            Self.logger.info(
                """
                Status item stop task completed action=\(stopAction?.loggingDescription ?? "none", privacy: .public) \
                recording_state=\(self.model.recordingState.loggingDescription, privacy: .public) \
                has_active_recording=\(self.model.hasActiveRecording, privacy: .public) \
                error_message=\(self.model.recordingActionErrorMessage ?? "none", privacy: .public)
                """
            )
            handleStatusItemStopAction(stopAction)
        }
        statusItemStopWatchdogTask = Task { @MainActor [weak self, statusItemStopWatchdogDelay] in
            do {
                try await Task.sleep(for: statusItemStopWatchdogDelay)
            } catch {
                return
            }

            self?.handleStatusItemStopWatchdog()
        }
    }

    private func handleStatusItemStopAction(_ stopAction: RecordingStopAction?) {
        statusItemStopWatchdogTask?.cancel()
        statusItemStopWatchdogTask = nil
        statusItemStopTask = nil
        isHandlingStatusItemStop = false
        Self.logger.info(
            "Status item stop action handled action=\(stopAction?.loggingDescription ?? "none", privacy: .public)"
        )

        switch stopAction {
        case .openEditor(let fileURL):
            windowPresenter.openEditor(fileURL: fileURL)
        case .quickExported, .audioRecorded, nil:
            break
        }
    }

    private func handleStatusItemStopWatchdog() {
        guard isHandlingStatusItemStop else {
            return
        }

        guard model.hasActiveRecording else {
            Self.logger.info("Status item stop watchdog cleared because recording is no longer active")
            statusItemStopWatchdogTask = nil
            isHandlingStatusItemStop = false
            return
        }

        statusItemStopTask?.cancel()
        Self.logger.fault(
            """
            Status item stop watchdog terminating app recording_state=\(self.model.recordingState.loggingDescription, privacy: .public) \
            active_recording=\(self.model.recordingState.activeRecording?.name ?? "none", privacy: .private)
            """
        )
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        Task {
            await model.handleAutomationURL(
                url,
                openSettings: { [weak windowPresenter] in
                    windowPresenter?.openSettings()
                },
                openRecording: { [weak windowPresenter] recordingURL in
                    windowPresenter?.openEditor(fileURL: recordingURL)
                }
            )
        }
    }

    private func startRecordingAnimation() {
        guard recordingAnimationTimer == nil else {
            return
        }

        recordingFrameIndex = 0
        setRecordingFrame()

        let timer = Timer(timeInterval: 1.0 / 18.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceRecordingFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        recordingAnimationTimer = timer
    }

    private func stopRecordingAnimation() {
        recordingAnimationTimer?.invalidate()
        recordingAnimationTimer = nil
        recordingFrameIndex = 0
    }

    private func advanceRecordingFrame() {
        recordingFrameIndex = (recordingFrameIndex + 1) % 18
        setRecordingFrame()
    }

    private func setRecordingFrame() {
        let presentation = model.recordingPresentation()
        let frame = makeActiveRecordingFrame(
            pulse: recordingPulse(for: recordingFrameIndex),
            elapsedText: presentation.menuBarTitle,
            audioLevel: model.audioLevelSample
        )
        setButtonImage(
            frame,
            key: "recording-\(recordingFrameIndex)-\(presentation.menuBarTitle)-\(model.audioLevelSample)"
        )
    }

    private func setButtonImage(_ image: NSImage?, key: String) {
        guard currentImageKey != key else {
            return
        }

        statusItem.button?.image = image
        currentImageKey = key
    }

    private func symbolImage(named name: String, accessibilityLabel: String) -> NSImage? {
        guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityLabel) else {
            return nil
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = baseImage.withSymbolConfiguration(configuration) ?? baseImage
        image.isTemplate = true
        image.size = iconSize
        return image
    }

    private func recordingPulse(for frame: Int) -> Double {
        let phase = Double(frame) / 18.0
        return 0.5 - (cos(phase * 2.0 * .pi) * 0.5)
    }

    private func makeActiveRecordingFrame(
        pulse: Double,
        elapsedText: String,
        audioLevel: AudioLevelSample
    ) -> NSImage {
        let width = activeStatusItemWidth(elapsedText: elapsedText)
        let size = NSSize(width: width, height: activeIconHeight)
        let image = NSImage(size: size)
        image.lockFocus()

        drawActiveRecordingFrame(
            in: NSRect(origin: .zero, size: size),
            pulse: pulse,
            elapsedText: elapsedText,
            audioLevel: audioLevel
        )

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func countdownStatusItemWidth(countdownText: String) -> CGFloat {
        let textWidth = ceil(countdownAttributedText(countdownText).size().width)
        return max(NSStatusItem.squareLength, textWidth + 12)
    }

    private func countdownTextImage(text: String, accessibilityLabel: String) -> NSImage {
        let width = countdownStatusItemWidth(countdownText: text)
        let size = NSSize(width: width, height: iconSize.height)
        let image = NSImage(size: size)
        image.accessibilityDescription = accessibilityLabel
        image.lockFocus()

        let attributedText = countdownAttributedText(text)
        let textSize = attributedText.size()
        attributedText.draw(at: NSPoint(
            x: (width - textSize.width) / 2,
            y: (iconSize.height - textSize.height) / 2
        ))

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func countdownAttributedText(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
        )
    }

    private func activeStatusItemWidth(elapsedText: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(
            string: elapsedText,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
        )
        let textWidth = elapsedText.isEmpty ? 0 : ceil(text.size().width)
        let waveformWidth: CGFloat = 46
        let contentWidth = 12 + 11 + 12 + waveformWidth + 12 + textWidth + 14 + 11 + 12
        return max(activeIconMinWidth, contentWidth)
    }

    private func drawActiveRecordingFrame(
        in rect: NSRect,
        pulse: Double,
        elapsedText: String,
        audioLevel: AudioLevelSample
    ) {
        let width = rect.width
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let text = NSAttributedString(
            string: elapsedText,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.9),
            ]
        )
        let waveformWidth: CGFloat = 46

        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: 1, y: 1, width: width - 2, height: activeIconHeight - 2),
            xRadius: activeIconHeight / 2,
            yRadius: activeIconHeight / 2
        ).fill()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let strokePath = NSBezierPath(
            roundedRect: NSRect(x: 1.5, y: 1.5, width: width - 3, height: activeIconHeight - 3),
            xRadius: (activeIconHeight - 3) / 2,
            yRadius: (activeIconHeight - 3) / 2
        )
        strokePath.lineWidth = 1
        strokePath.stroke()

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: 6.5, width: 11, height: 11)).fill()

        drawWaveform(
            in: NSRect(x: 35, y: 4, width: waveformWidth, height: 16),
            pulse: pulse,
            audioLevel: audioLevel
        )

        if !elapsedText.isEmpty {
            text.draw(at: NSPoint(x: 93, y: 4.5))
        }

        NSColor.white.withAlphaComponent(0.86).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: width - 23, y: 7, width: 10, height: 10),
            xRadius: 2,
            yRadius: 2
        ).fill()
    }

    private func drawWaveform(
        in rect: NSRect,
        pulse: Double,
        audioLevel: AudioLevelSample
    ) {
        let bars: [CGFloat] = [
            0.30, 0.72, 0.42, 0.88, 0.56, 0.78, 0.34,
            0.64, 0.92, 0.50, 0.76, 0.44, 0.70, 0.36,
        ]
        let level = max(0.18, CGFloat(audioLevel.peak))
        let animatedLevel = min(1, level + (CGFloat(pulse) * 0.18))
        let barWidth: CGFloat = 2
        let step = rect.width / CGFloat(bars.count)

        for (index, bar) in bars.enumerated() {
            let height = max(3, rect.height * min(1, bar * (0.55 + animatedLevel)))
            let x = rect.minX + (CGFloat(index) * step) + ((step - barWidth) / 2)
            let y = rect.midY - (height / 2)

            if index < 6 {
                NSColor.systemRed.withAlphaComponent(0.95).setFill()
            } else {
                NSColor.white.withAlphaComponent(0.76).setFill()
            }

            NSBezierPath(
                roundedRect: NSRect(x: x, y: y, width: barWidth, height: height),
                xRadius: 1,
                yRadius: 1
            ).fill()
        }
    }
}

extension LuxelStatusItemController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              panel === menuPanel else {
            return
        }

        closePopover()
    }
}

private final class LuxelMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private struct LuxelMenuPanelChrome<Content: View>: View {
    let arrowCenterX: CGFloat
    let arrowHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let shape = LuxelMenuPanelShape(arrowCenterX: arrowCenterX, arrowHeight: arrowHeight)

        content
            .padding(.top, arrowHeight)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .stroke(.white.opacity(0.34), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .background(Color.clear)
    }
}

private struct LuxelMenuPanelShape: Shape {
    let arrowCenterX: CGFloat
    let arrowHeight: CGFloat
    private let arrowWidth: CGFloat = 24
    private let panelCornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let bodyMinY = rect.minY + arrowHeight
        let bodyHeight = rect.maxY - bodyMinY
        let radius = min(panelCornerRadius, rect.width / 2, bodyHeight / 2)
        let arrowHalfWidth = arrowWidth / 2
        let centerX = min(
            max(arrowCenterX, rect.minX + radius + arrowHalfWidth),
            rect.maxX - radius - arrowHalfWidth
        )
        let arrowLeft = centerX - arrowHalfWidth
        let arrowRight = centerX + arrowHalfWidth
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: bodyMinY))
        path.addLine(to: CGPoint(x: arrowLeft, y: bodyMinY))
        path.addLine(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: arrowRight, y: bodyMinY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyMinY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyMinY + radius),
            control: CGPoint(x: rect.maxX, y: bodyMinY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyMinY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: bodyMinY),
            control: CGPoint(x: rect.minX, y: bodyMinY)
        )
        path.closeSubpath()

        return path
    }
}

private final class LuxelMenuPanelContentView: NSView {
    private let arrowHeight: CGFloat
    private let maskLayer = CAShapeLayer()

    var arrowCenterX: CGFloat = 0 {
        didSet {
            needsLayout = true
        }
    }

    init(frame frameRect: NSRect, arrowHeight: CGFloat) {
        self.arrowHeight = arrowHeight
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = maskLayer
        maskLayer.fillColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        maskLayer.frame = bounds
        maskLayer.path = LuxelMenuPanelPath.bezierPath(
            in: bounds,
            arrowCenterX: arrowCenterX,
            arrowHeight: arrowHeight
        ).cgPath
    }
}

private enum LuxelMenuPanelPath {
    static let cornerRadius: CGFloat = 22
    private static let arrowWidth: CGFloat = 24

    static func bezierPath(
        in bounds: CGRect,
        arrowCenterX: CGFloat,
        arrowHeight: CGFloat
    ) -> NSBezierPath {
        guard arrowHeight > 0 else {
            return NSBezierPath(
                roundedRect: bounds,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
        }

        let bodyMaxY = bounds.maxY - arrowHeight
        let radius = min(cornerRadius, bounds.width / 2, bodyMaxY / 2)
        let arrowHalfWidth = arrowWidth / 2
        let centerX = min(
            max(arrowCenterX, bounds.minX + radius + arrowHalfWidth),
            bounds.maxX - radius - arrowHalfWidth
        )
        let arrowLeft = centerX - arrowHalfWidth
        let arrowRight = centerX + arrowHalfWidth
        let path = NSBezierPath()

        path.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.line(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.curve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + radius),
            controlPoint1: CGPoint(x: bounds.maxX, y: bounds.minY),
            controlPoint2: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.line(to: CGPoint(x: bounds.maxX, y: bodyMaxY - radius))
        path.curve(
            to: CGPoint(x: bounds.maxX - radius, y: bodyMaxY),
            controlPoint1: CGPoint(x: bounds.maxX, y: bodyMaxY),
            controlPoint2: CGPoint(x: bounds.maxX, y: bodyMaxY)
        )
        path.line(to: CGPoint(x: arrowRight, y: bodyMaxY))
        path.line(to: CGPoint(x: centerX, y: bounds.maxY))
        path.line(to: CGPoint(x: arrowLeft, y: bodyMaxY))
        path.line(to: CGPoint(x: bounds.minX + radius, y: bodyMaxY))
        path.curve(
            to: CGPoint(x: bounds.minX, y: bodyMaxY - radius),
            controlPoint1: CGPoint(x: bounds.minX, y: bodyMaxY),
            controlPoint2: CGPoint(x: bounds.minX, y: bodyMaxY)
        )
        path.line(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))
        path.curve(
            to: CGPoint(x: bounds.minX + radius, y: bounds.minY),
            controlPoint1: CGPoint(x: bounds.minX, y: bounds.minY),
            controlPoint2: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.close()

        return path
    }
}
