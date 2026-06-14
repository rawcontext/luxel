import AppKit
import Carbon
import LuxelCore
import LuxelPresentation
import SwiftUI

@MainActor
final class LuxelStatusItemController: NSObject {
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
    private var isHandlingStatusItemStop = false
    private var statusItemStopTask: Task<Void, Never>?
    private var statusItemStopWatchdogTask: Task<Void, Never>?

    private let iconSize = NSSize(width: 18, height: 18)
    private let statusItemStopWatchdogDelay: Duration = .seconds(8)
    private lazy var recordingFrames = makeRecordingFrames()

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
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.imagePosition = .imageOnly
        button.setButtonType(.momentaryChange)
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
        let presentation = model.menuBarStatusPresentation()
        statusItem.button?.toolTip = presentation.accessibilityLabel
        statusItem.button?.setAccessibilityLabel(presentation.accessibilityLabel)

        if presentation.animatesMenuBarSystemImage {
            startRecordingAnimation()
        } else {
            stopRecordingAnimation()
            setButtonImage(
                symbolImage(named: presentation.menuBarSystemImage, accessibilityLabel: presentation.accessibilityLabel),
                key: presentation.menuBarSystemImage
            )
        }

        quickExportProgressPanelController.update(progress: model.quickExportProgress) { [weak model] in
            model?.cancelQuickExport()
        }
    }

    @objc private func handleStatusItemClick() {
        if model.hasActiveRecording {
            stopRecordingFromStatusItem()
            return
        }

        togglePopover()
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
            return
        }

        isHandlingStatusItemStop = true
        popover.performClose(nil)

        statusItemStopTask?.cancel()
        statusItemStopWatchdogTask?.cancel()

        statusItemStopTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let stopAction = await model.stopRecording()
            guard !Task.isCancelled else {
                return
            }

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
            statusItemStopWatchdogTask = nil
            isHandlingStatusItemStop = false
            return
        }

        statusItemStopTask?.cancel()
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
        recordingFrameIndex = (recordingFrameIndex + 1) % recordingFrames.count
        setRecordingFrame()
    }

    private func setRecordingFrame() {
        setButtonImage(recordingFrames[recordingFrameIndex], key: "recording-\(recordingFrameIndex)")
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

    private func makeRecordingFrames() -> [NSImage] {
        let frameCount = 18

        return (0..<frameCount).compactMap { frame in
            let phase = Double(frame) / Double(frameCount)
            let pulse = 0.5 - (cos(phase * 2.0 * .pi) * 0.5)
            return makeRecordingFrame(pulse: pulse)
        }
    }

    private func makeRecordingFrame(pulse: Double) -> NSImage? {
        guard
            let baseImage = symbolImage(named: "record.circle", accessibilityLabel: "Luxel recording"),
            let fillImage = symbolImage(named: "record.circle.fill", accessibilityLabel: "Luxel recording")
        else {
            return symbolImage(named: "record.circle", accessibilityLabel: "Luxel recording")
        }

        let image = NSImage(size: iconSize)
        image.lockFocus()

        let bounds = NSRect(origin: .zero, size: iconSize)
        baseImage.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)

        let scale = 0.92 + (pulse * 0.16)
        let side = iconSize.width * scale
        let overlayRect = NSRect(
            x: (iconSize.width - side) / 2,
            y: (iconSize.height - side) / 2,
            width: side,
            height: side
        )
        fillImage.draw(
            in: overlayRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 0.18 + (pulse * 0.54)
        )

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
