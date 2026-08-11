import AppKit
import Carbon
import LuxelCore
import LuxelPresentation
import OSLog
import SwiftUI

@MainActor
final class LuxelStatusItemController: NSObject {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.rawcontext.luxel",
        category: "StatusItem"
    )

    let model: LuxelMenuModel
    let editorModel: LuxelEditorModel
    let cropperPanelController: LuxelCropperPanelController
    let shortcutController: LuxelShortcutController
    let windowPresenter: LuxelWindowPresenter
    let quickExportProgressPanelController = QuickExportProgressPanelController()

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var statusRefreshTimer: Timer?
    var recordingAnimationTimer: Timer?
    var recordingFrameIndex = 0
    var recordingLevelHistory: [CGFloat] = []
    var currentImageKey: String?
    var currentStatusItemLength = NSStatusItem.squareLength
    var isHandlingStatusItemStop = false
    var statusItemStopTask: Task<Void, Never>?
    var statusItemStopWatchdogTask: Task<Void, Never>?
    var recordingAudioLevelTask: Task<Void, Never>?
    var recordingAudioLevelTaskID: String?
    var notchDisplayTask: Task<Void, Never>?
    var notchInteractionTask: Task<Void, Never>?
    var notchSurfaceRefreshTask: Task<Void, Never>?
    var replayBufferStateTask: Task<Void, Never>?
    var applicationResignActiveObserver: NSObjectProtocol?
    var menuPanel: NSPanel?
    var menuHostingController: NSHostingController<AnyView>?
    var pendingPopoverOpenTask: Task<Void, Never>?
    var suppressNextPopoverOpenUntil: Date?
    var activationSourceApplication: NSRunningApplication?
    var isPresentingPermissionPrompt = false
    var isPresentingReplayBufferConsent = false

    let iconSize = NSSize(width: 18, height: 18)
    let activeIconHeight: CGFloat = 24
    let activeIconMinWidth: CGFloat = 118
    let menuPanelWidth: CGFloat = 320
    let menuPanelFallbackHeight: CGFloat = 250
    let menuPanelMinimumHeight: CGFloat = 130
    let menuPanelFittingHeightPadding: CGFloat = 10
    let menuPanelHorizontalOffset: CGFloat = -4
    let statusItemStopWatchdogDelay: Duration = .seconds(8)

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
        startReplayBuffer()
        startNotchSurface()
        refreshStatusItem()
        recoverInterruptedRecording()
    }
}

extension LuxelStatusItemController {
    func configureStatusItem() {
        let autosaveIdentifier =
            Bundle.main.bundleIdentifier
            .map { "\($0).statusItem" } ?? "com.rawcontext.luxel.statusItem"
        statusItem.autosaveName = NSStatusItem.AutosaveName(autosaveIdentifier)

        guard let button = statusItem.button else {
            return
        }

        configureStatusItemButton(button)
    }

    func configureStatusItemButton(_ button: NSStatusBarButton) {
        button.target = self
        button.action = #selector(handleStatusItemClick)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.setButtonType(.momentaryChange)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        Self.logger.debug("Status item button configured")
    }

    func configurePopover() {
        let hostingController = LuxelMenuHostingController(
            rootView: makeMenuRootView()
        )
        hostingController.view.frame = NSRect(origin: .zero, size: fallbackMenuPanelSize)
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.isOpaque = false
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        menuHostingController = hostingController
    }

    func makeMenuRootView() -> AnyView {
        AnyView(
            LuxelMenuPanelChrome {
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

    func installPopoverDismissalObserver() {
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

    func closePopoverAfterAppDeactivation() {
        guard isPopoverShown else {
            return
        }

        if isMouseOverStatusItemButton {
            suppressNextPopoverOpenUntil = Date().addingTimeInterval(0.35)
        }

        closePopover()
    }

    func recoverInterruptedRecording() {
        Task { @MainActor [weak self] in
            guard let self,
                  let recording = await model.recoverInterruptedRecording()
            else {
                return
            }

            windowPresenter.openEditor(fileURL: recording.fileURL)
        }
    }

    func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func startStatusRefresh() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        statusRefreshTimer = timer
    }

    func startReplayBuffer() {
        replayBufferStateTask = Task { @MainActor [weak model] in
            await model?.watchReplayBufferState()
        }
        Task { @MainActor [weak model] in
            await model?.reconcileReplayBufferOnLaunch()
        }
    }

    func refreshStatusItem() {
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

    var shouldShowMenuBarIcon: Bool {
        !model.settings.hideMenuBarIcon || !model.settings.notchSurfaceSettings.isEnabled
    }

    func setStatusItemVisible(_ isVisible: Bool) {
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

    func refreshStatusItemPanels() {
        quickExportProgressPanelController.update(progress: model.quickExportProgress) { [weak model] in
            model?.cancelQuickExport()
        }
        presentPendingReplayBufferConsentIfNeeded()
        presentPendingPermissionPromptIfNeeded()
        refreshNotchSurface()
    }

    func setStatusItemLength(_ length: CGFloat) {
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

    func refreshRecordingAudioLevelMonitoring() {
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

    func stopRecordingAudioLevelMonitoring() {
        guard recordingAudioLevelTask != nil || recordingAudioLevelTaskID != nil else {
            return
        }

        recordingAudioLevelTask?.cancel()
        recordingAudioLevelTask = nil
        recordingAudioLevelTaskID = nil
        model.audioLevelSample = .silent
    }

    @objc func handleStatusItemClick() {
        Self.logger.info(
            """
      Status item clicked has_active_recording=\(self.model.hasActiveRecording, privacy: .public) \
      recording_state=\(self.model.recordingState.loggingDescription, privacy: .public) \
      is_handling_stop=\(self.isHandlingStatusItemStop, privacy: .public) \
      button_configured=\(self.isStatusItemButtonConfigured, privacy: .public) \
      popover_shown=\(self.isPopoverShown, privacy: .public)
      """
        )

        if NSApp.currentEvent?.type == .rightMouseUp {
            rememberActivationSourceApplication()
            showStatusItemQuickActionsMenu()
            return
        }

        if model.hasActiveRecording {
            stopRecordingFromStatusItem()
            return
        }

        rememberActivationSourceApplication()
        togglePopover()
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
