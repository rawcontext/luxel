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
    private let popover = NSPopover()
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

    private let iconSize = NSSize(width: 18, height: 18)
    private let activeIconHeight: CGFloat = 24
    private let activeIconMinWidth: CGFloat = 118
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
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 284, height: 720)
        popover.contentViewController = NSHostingController(
            rootView: LuxelMenu(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController,
                openEditorWindow: { [weak windowPresenter] in
                    windowPresenter?.openEditor()
                },
                openSettingsWindow: { [weak windowPresenter] in
                    windowPresenter?.openSettings()
                }
            )
        )
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

        let presentation = model.recordingPresentation()
        statusItem.button?.toolTip = presentation.accessibilityLabel
        statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)

        if presentation.animatesMenuBarSystemImage {
            setStatusItemLength(activeStatusItemWidth(elapsedText: presentation.menuBarTitle))
            startRecordingAnimation()
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
            popover_shown=\(self.popover.isShown, privacy: .public)
            """
        )

        if model.hasActiveRecording {
            stopRecordingFromStatusItem()
            return
        }

        togglePopover()
    }

    private var isStatusItemButtonConfigured: Bool {
        guard let button = statusItem.button else {
            return false
        }

        return button.target === self && button.action == #selector(handleStatusItemClick)
    }

    private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
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
        popover.performClose(nil)
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
