import AppKit
import LuxelCore
import LuxelPresentation
import OSLog
import SwiftUI

extension LuxelStatusItemController {
    func openPopover() {
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

    func prepareMenuForPopover() async {
        model.refreshRecentRecordings()
        await model.refreshPermissions()
        await model.refreshCaptureTargets()
        await Task.yield()
    }

    func showPopover(relativeTo button: NSStatusBarButton) {
        model.refreshRecentRecordings()
        menuHostingController?.rootView = makeMenuRootView()

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

    func updateMenuPanelFrame(
        _ panel: NSPanel,
        relativeTo button: NSStatusBarButton,
        display: Bool
    ) {
        layoutStatusItemButton(button)

        let panelSize = fittedMenuPanelSize()
        let frame = menuPanelFrame(relativeTo: button, panelSize: panelSize)
        panel.setFrame(frame, display: display)
        panel.contentView?.layoutSubtreeIfNeeded()
    }

    func layoutStatusItemButton(_ button: NSStatusBarButton) {
        button.window?.contentView?.layoutSubtreeIfNeeded()
        button.superview?.layoutSubtreeIfNeeded()
        button.layoutSubtreeIfNeeded()
    }

    func closePopover() {
        pendingPopoverOpenTask?.cancel()
        pendingPopoverOpenTask = nil
        menuPanel?.orderOut(nil)
    }

    var fallbackMenuPanelSize: NSSize {
        NSSize(width: menuPanelWidth, height: menuPanelFallbackHeight)
    }

    func fittedMenuPanelSize() -> NSSize {
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

    func makeMenuPanel() -> NSPanel {
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

    func makeMenuPanelContentView() -> NSView {
        let container = LuxelMenuPanelContentView(
            frame: NSRect(origin: .zero, size: fallbackMenuPanelSize)
        )

        if let hostingView = menuHostingController?.view {
            hostingView.frame = container.bounds
            hostingView.autoresizingMask = [.width, .height]
            hostingView.wantsLayer = true
            hostingView.layer?.isOpaque = false
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            container.addSubview(hostingView)
        }

        return container
    }

    func menuPanelFrame(
        relativeTo button: NSStatusBarButton,
        panelSize: NSSize
    ) -> NSRect {
        let buttonFrame = statusItemButtonFrame(relativeTo: button)
        let anchorMidX = buttonFrame.midX + menuPanelHorizontalOffset
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

        return NSRect(origin: NSPoint(x: originX, y: originY), size: panelSize)
    }

    func statusItemButtonFrame(relativeTo button: NSStatusBarButton) -> NSRect {
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

    func stopRecordingFromStatusItem() {
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

    func startStatusItemStopTask() {
        guard isHandlingStatusItemStop else {
            return
        }

        statusItemStopTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let recordingState = self.model.recordingState.loggingDescription
            Self.logger.info(
                "Status item stop task started recording_state=\(recordingState, privacy: .public)")
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

    func handleStatusItemStopAction(_ stopAction: RecordingStopAction?) {
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

    func handleStatusItemStopWatchdog() {
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
        let recordingState = model.recordingState.loggingDescription
        let recordingName = model.recordingState.activeRecording?.name ?? "none"
        Self.logger.fault(
            """
            Status item stop watchdog terminating app recording_state=\(recordingState, privacy: .public) \
            active_recording=\(recordingName, privacy: .private)
            """
        )
        NSApplication.shared.terminate(nil)
    }

    @objc func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        Task { [model, windowPresenter] in
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
