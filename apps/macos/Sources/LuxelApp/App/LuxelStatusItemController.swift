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
    private var notchDisplayTask: Task<Void, Never>?
    private var notchInteractionTask: Task<Void, Never>?
    private var notchSurfaceRefreshTask: Task<Void, Never>?
    private var applicationResignActiveObserver: NSObjectProtocol?
    private var menuPanel: NSPanel?
    private var menuHostingController: NSHostingController<AnyView>?
    private var menuPanelContentView: LuxelMenuPanelContentView?
    private var pendingPopoverOpenTask: Task<Void, Never>?
    private var suppressNextPopoverOpenUntil: Date?
    private var activationSourceApplication: NSRunningApplication?
    private var isPresentingPermissionPrompt = false

    let iconSize = NSSize(width: 18, height: 18)
    let activeIconHeight: CGFloat = 24
    let activeIconMinWidth: CGFloat = 118
    private let menuPanelWidth: CGFloat = 324
    private let menuPanelFallbackHeight: CGFloat = 260
    private let menuPanelMinimumHeight: CGFloat = 150
    private let menuPanelFittingHeightPadding: CGFloat = 8
    private let menuPanelArrowHeight: CGFloat = 10
    private let menuPanelArrowHorizontalOffset: CGFloat = -4
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
        startNotchSurface()
        refreshStatusItem()
        recoverInterruptedRecording()
    }
}

extension LuxelStatusItemController {
    private func configureStatusItem() {
        let autosaveIdentifier =
            Bundle.main.bundleIdentifier
            .map { "\($0).statusItem" } ?? "media.luxel.app.statusItem"
        statusItem.autosaveName = NSStatusItem.AutosaveName(autosaveIdentifier)

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
        button.sendAction(on: [.leftMouseUp])
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
                    },
                    presentPermissionPrompt: { [weak self] source in
                        self?.presentPermissionPrompt(for: source)
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
                  let recording = await model.recoverInterruptedRecording()
            else {
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

        let shouldShowStatusItem = shouldShowMenuBarIcon
        setStatusItemVisible(shouldShowStatusItem)
        if !shouldShowStatusItem {
            stopRecordingAnimation()
            refreshStatusItemPanels()
            return
        }

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

        refreshStatusItemPanels()
    }

    private var shouldShowMenuBarIcon: Bool {
        !model.settings.hideMenuBarIcon || !model.settings.notchSurfaceSettings.isEnabled
    }

    private func setStatusItemVisible(_ isVisible: Bool) {
        guard statusItem.isVisible != isVisible else {
            return
        }

        statusItem.isVisible = isVisible
        currentImageKey = nil

        if isVisible {
            if let button = statusItem.button {
                configureStatusItemButton(button)
            }
        } else {
            closePopover()
        }
    }

    private func refreshStatusItemPanels() {
        quickExportProgressPanelController.update(progress: model.quickExportProgress) { [weak model] in
            model?.cancelQuickExport()
        }
        presentPendingPermissionPromptIfNeeded()
        refreshNotchSurface()
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
              activeRecording.options.audio.capturesAudio
        else {
            stopRecordingAudioLevelMonitoring()
            return
        }

        let taskID = [
            model.recordingAudioLevelMonitorTaskID,
            activeRecording.fileURL.path,
            String(describing: activeRecording.options.audio)
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
              frontmostApplication.processIdentifier != NSRunningApplication.current.processIdentifier
        else {
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

    private func presentPendingPermissionPromptIfNeeded() {
        guard !isPresentingPermissionPrompt,
              let prompt = model.permissionPrompt
        else {
            return
        }

        presentPermissionPrompt(prompt)
    }

    private func presentPermissionPrompt(for source: CapturePermissionSource) {
        presentPermissionPrompt(model.makePermissionPrompt(forSource: source))
    }

    private func presentPermissionPrompt(_ prompt: PermissionPrompt) {
        guard !isPresentingPermissionPrompt else {
            model.permissionPrompt = prompt
            return
        }

        isPresentingPermissionPrompt = true
        model.permissionPrompt = nil
        closePopover()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else {
                return
            }

            let shouldPerformAction = runPermissionAlert(prompt)
            isPresentingPermissionPrompt = false

            if shouldPerformAction {
                await model.performPermissionAction(prompt)
            } else {
                model.permissionPrompt = nil
            }

            presentPendingPermissionPromptIfNeeded()
        }
    }

    private func runPermissionAlert(_ prompt: PermissionPrompt) -> Bool {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = prompt.guidance.title
        alert.informativeText = prompt.guidance.message

        let primaryButton = alert.addButton(withTitle: prompt.guidance.actionTitle)
        primaryButton.keyEquivalent = "\r"
        primaryButton.keyEquivalentModifierMask = []

        let cancelButton = alert.addButton(withTitle: "Cancel")
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.keyEquivalentModifierMask = []

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func startNotchSurface() {
        model.refreshNotchDisplays()
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.refreshPermissions()
            refreshNotchSurface()
        }
        notchDisplayTask = Task { @MainActor [weak model] in
            await model?.watchNotchDisplayUpdates()
        }
        notchInteractionTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.watchNotchInteractions(
                openEditor: { [weak self] fileURL in
                    self?.windowPresenter.openEditor(fileURL: fileURL)
                },
                openSettings: { [weak self] in
                    self?.windowPresenter.openSettings()
                },
                showAreaCapturePicker: { [weak self] in
                    self?.showNotchAreaCapturePicker()
                }
            )
        }
        refreshNotchSurface()
    }

    private func refreshNotchSurface() {
        notchSurfaceRefreshTask?.cancel()
        notchSurfaceRefreshTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await model.refreshNotchSurface(
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
    }

    private func showNotchAreaCapturePicker() {
        showNotchCapturePicker(recordingActionID: .recordArea)
    }

    private func showNotchCapturePicker(
        recordingActionID: NotchActivityActionID?
    ) {
        model.refreshCameraDevices()
        cropperPanelController.show(
            countdownDuration: model.settings.defaultCountdown,
            stopAfterDuration: model.settings.lastStopAfter,
            canRecordAudio: model.microphoneStatus == .authorized,
            cameraConfiguration: model.cropperCameraConfiguration(),
            quickRecordingConfiguration: model.cropperQuickRecordingConfiguration(),
            selectionPresetConfiguration: model.cropperSelectionPresetConfiguration(),
            restoreSelectionConfiguration: model.cropperRestoreSelectionConfiguration(),
            recordAudio: model.captureCapabilities.microphoneTrackAvailable,
            loupeAlwaysOn: model.settings.loupeAlwaysOn,
            dimOtherDisplays: model.settings.dimOtherDisplays,
            showsNotificationReminder: false,
            onCountdownDurationChange: { [weak model] duration in
                model?.settings.defaultCountdown = duration
                model?.saveSettings()
            },
            onStopAfterDurationChange: { [weak model] duration in
                model?.settings.lastStopAfter = duration
                model?.saveSettings()
            },
            onRecordAudioChange: { [weak self, weak model] isEnabled in
                guard !isEnabled || model?.microphoneStatus == .authorized else {
                    self?.presentPermissionPrompt(for: .microphone)
                    return
                }

                model?.settings.recordAudio = isEnabled
                model?.saveSettings()
            },
            onCameraSelectionChange: { [weak model] deviceID in
                Task {
                    await model?.setCameraDeviceFromCropper(deviceID)
                }
            },
            onCameraPreviewStyleChange: { [weak model] style in
                Task {
                    await model?.setCameraPreviewStyleFromCropper(style)
                }
            },
            onNotificationReminderDismiss: { [weak model] in
                model?.dismissNotificationReminder()
            },
            onQuickSelect: { [weak model] draft, presetID in
                Task {
                    await model?.startQuickRecording(
                        from: draft,
                        presetID: presetID,
                        notchRecordingActionID: recordingActionID
                    )
                }
            },
            onSelect: { [weak model] draft in
                Task {
                    await model?.startRecording(
                        from: draft,
                        notchRecordingActionID: recordingActionID
                    )
                }
            }
        )
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
        } else if shouldSuppressRecentPopoverOpen {
            suppressNextPopoverOpenUntil = nil
        } else {
            openPopover()
        }
    }

    private var isPopoverShown: Bool {
        menuPanel?.isVisible == true
    }

    private var shouldSuppressRecentPopoverOpen: Bool {
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
        guard let button = statusItem.button else {
            return false
        }

        let buttonFrame = statusItemButtonFrame(relativeTo: button)
            .insetBy(dx: -4, dy: -4)
        return buttonFrame.contains(NSEvent.mouseLocation)
    }
}

extension LuxelStatusItemController {
    private func openPopover() {
        pendingPopoverOpenTask?.cancel()
        pendingPopoverOpenTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await prepareMenuForPopover()

            guard !Task.isCancelled,
                  let button = statusItem.button
            else {
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
                  let button = self.statusItem.button
            else {
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

        let fittingSize = menuHostingController.sizeThatFits(
            in: CGSize(
                width: menuPanelWidth,
                height: CGFloat.greatestFiniteMagnitude
            ))
        let fittedHeight =
            fittingSize.height.isFinite && fittingSize.height > 0
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
        let buttonFrame = statusItemButtonFrame(relativeTo: button)
        let anchorMidX = buttonFrame.midX + menuPanelArrowHorizontalOffset
        let screenFrame =
            button.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let margin: CGFloat = 8
        let originX = min(
            max(anchorMidX - panelSize.width / 2, screenFrame.minX + margin),
            screenFrame.maxX - panelSize.width - margin
        )
        let topY = buttonFrame.minY > 0 ? buttonFrame.minY : screenFrame.maxY
        let originY = topY - panelSize.height
        let frame = NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize)
        let arrowCenterX = anchorMidX - frame.minX

        return (frame, arrowCenterX)
    }

    private func statusItemButtonFrame(relativeTo button: NSStatusBarButton) -> NSRect {
        guard let window = button.window else {
            return .zero
        }

        let convertedFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let accessibilityFrame = button.accessibilityFrame()
        guard accessibilityFrame.width > 0,
              accessibilityFrame.height > 0,
              accessibilityFrame.minX.isFinite
        else {
            return convertedFrame
        }

        return NSRect(
            x: accessibilityFrame.minX,
            y: convertedFrame.minY,
            width: accessibilityFrame.width,
            height: convertedFrame.height
        )
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

        DispatchQueue.main.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.startStatusItemStopTask()
            }
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

    private func startStatusItemStopTask() {
        guard isHandlingStatusItemStop else {
            return
        }

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
}

extension LuxelStatusItemController {
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

}

extension LuxelStatusItemController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              panel === menuPanel
        else {
            return
        }

        closePopover()
    }
}
