import AppKit
import Darwin
import LuxelCore
import LuxelPresentation
import SwiftUI
@preconcurrency import UserNotifications

@main
struct LuxelApp: App {
    @NSApplicationDelegateAdaptor(LuxelApplicationDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    @State private var model: LuxelMenuModel
    @State private var editorModel: LuxelEditorModel
    @State private var cropperPanelController: LuxelCropperPanelController
    @State private var shortcutController: LuxelShortcutController
    @State private var windowPresenter: LuxelWindowPresenter
    @State private var statusItemController: LuxelStatusItemController
    @State private var aboutWindowPresenter: LuxelAboutWindowPresenter

    init() {
        LuxelTooltipConfiguration.registerDefaults()
        LuxelSingleInstanceGuard.exitDuplicateInstanceIfNeeded()

        let errorReporter = LuxelCompositionRoot.errorReporter()
        let captureTargetCatalog = LuxelCompositionRoot.captureTargetCatalog()
        let captureTargetService = LuxelCompositionRoot.captureTargetService(
            catalog: captureTargetCatalog)
        let captureExclusionRegistry = CaptureExclusionRegistry()
        let model = LuxelMenuModel(
            captureTargetService: captureTargetService,
            captureExclusionRegistry: captureExclusionRegistry,
            cameraPreviewPanelController: LuxelCompositionRoot.cameraPreviewPanelController(),
            errorReporter: errorReporter
        )
        let editorModel = LuxelCompositionRoot.editorModel(errorReporter: errorReporter)
        let cropperPanelController = LuxelCropperPanelController(
            targetService: captureTargetService,
            exclusionRegistry: captureExclusionRegistry
        )
        let shortcutController = LuxelShortcutController()
        let aboutWindowPresenter = LuxelAboutWindowPresenter(metadata: model.appMetadata)
        let windowPresenter = LuxelWindowPresenter(
            model: model,
            editorModel: editorModel
        )

        _model = State(initialValue: model)
        _editorModel = State(initialValue: editorModel)
        _cropperPanelController = State(initialValue: cropperPanelController)
        _shortcutController = State(initialValue: shortcutController)
        _windowPresenter = State(initialValue: windowPresenter)
        _aboutWindowPresenter = State(initialValue: aboutWindowPresenter)
        _statusItemController = State(
            initialValue: LuxelStatusItemController(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController,
                windowPresenter: windowPresenter
            ))
    }

    var body: some Scene {
        LuxelSettingsActionScene(
            applicationDelegate: appDelegate,
            model: model,
            windowPresenter: windowPresenter,
            openSettingsAction: openSettings
        ) {
            WindowGroup(id: LuxelEditorScene.id) {
                LuxelEditorView(model: editorModel)
            }
            .defaultLaunchBehavior(.suppressed)
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About \(model.appMetadata.displayName)") {
                        aboutWindowPresenter.open()
                    }
                }
            }

            Settings {
                LuxelSettingsView(
                    model: model,
                    editorModel: editorModel,
                    cropperPanelController: cropperPanelController,
                    shortcutController: shortcutController,
                    openEditorWindow: {
                        windowPresenter.openEditor()
                    }
                )
                .navigationTitle("Luxel Settings")
                .luxelGlassSceneWindowChrome()
                .background {
                    LuxelSettingsWindowLifecycleObserver(
                        onWindowDidAppear: windowPresenter.settingsWindowDidAppear,
                        onWindowWillClose: windowPresenter.settingsWindowWillClose
                    )
                }
            }
            .defaultSize(width: 920, height: 760)
            .windowResizability(.contentMinSize)
            .windowBackgroundDragBehavior(.enabled)
        }
    }
}

enum LuxelTooltipConfiguration {
    // Native SwiftUI help tags read this AppKit registration default when the tooltip manager starts.
    static let initialDelayDefaultsKey = "NSInitialToolTipDelay"
    static let initialDelayMilliseconds = 500

    static func registerDefaults(in userDefaults: UserDefaults = .standard) {
        userDefaults.register(defaults: [
            initialDelayDefaultsKey: initialDelayMilliseconds
        ])
    }
}

private struct LuxelSettingsActionScene<Content: Scene>: Scene {
    let content: Content

    init(
        applicationDelegate: LuxelApplicationDelegate,
        model: LuxelMenuModel,
        windowPresenter: LuxelWindowPresenter,
        openSettingsAction: OpenSettingsAction,
        @SceneBuilder content: () -> Content
    ) {
        applicationDelegate.openFiles = { fileURLs, activationSource in
            guard let fileURL = fileURLs.first else {
                return
            }
            windowPresenter.openEditor(fileURL: fileURL, activationSource: activationSource)
        }
        applicationDelegate.openURLs = { urls in
            guard let url = urls.first else {
                return
            }
            Task { @MainActor in
                await model.handleAutomationURL(
                    url,
                    openSettings: { windowPresenter.openSettings() },
                    openRecording: { windowPresenter.openEditor(fileURL: $0) }
                )
            }
        }
        applicationDelegate.installURLHandler()
        applicationDelegate.voiceDetectionPromptActions = { [weak model] action in
            Task { @MainActor in
                await model?.handleVoiceDetectionPromptAction(action)
            }
        }
        applicationDelegate.prepareForTermination = { [weak model] in
            await model?.shutdownVoiceDetection()
        }
        windowPresenter.install(openSettingsAction: openSettingsAction)
        self.content = content()
    }

    var body: some Scene {
        content
    }
}

@MainActor
final class LuxelApplicationDelegate: NSObject, NSApplicationDelegate {
    var openFiles: (([URL], NSRunningApplication?) -> Void)?
    var openURLs: (([URL]) -> Void)? {
        didSet {
            guard let openURLs, !pendingURLs.isEmpty else {
                return
            }
            let urls = pendingURLs
            pendingURLs.removeAll()
            openURLs(urls)
        }
    }
    private var pendingURLs: [URL] = []
    var voiceDetectionPromptActions: ((VoiceDetectionPromptAction) -> Void)? {
        didSet {
            guard let voiceDetectionPromptActions, !pendingVoiceDetectionPromptActions.isEmpty else {
                return
            }
            let actions = pendingVoiceDetectionPromptActions
            pendingVoiceDetectionPromptActions.removeAll()
            actions.forEach(voiceDetectionPromptActions)
        }
    }
    private var pendingVoiceDetectionPromptActions: [VoiceDetectionPromptAction] = []
    private var voiceDetectionNotificationController: VoiceDetectionNotificationController?
    var prepareForTermination: (@MainActor () async -> Void)?
    private var terminationTask: Task<Void, Never>?

    func applicationWillFinishLaunching(_: Notification) {
        installURLHandler()
        installVoiceDetectionNotificationController()
    }

    func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationWillTerminate(_: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let prepareForTermination else {
            return .terminateNow
        }
        guard terminationTask == nil else {
            return .terminateLater
        }

        terminationTask = Task { @MainActor [weak self] in
            await prepareForTermination()
            sender.reply(toApplicationShouldTerminate: true)
            self?.terminationTask = nil
        }
        return .terminateLater
    }

    func handleVoiceDetectionPromptAction(_ action: VoiceDetectionPromptAction) {
        if let voiceDetectionPromptActions {
            voiceDetectionPromptActions(action)
        } else {
            pendingVoiceDetectionPromptActions.append(action)
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        if !fileURLs.isEmpty {
            openFiles?(fileURLs, NSWorkspace.shared.frontmostApplication)
        }
        let automationURLs = urls.filter { !$0.isFileURL }
        if !automationURLs.isEmpty {
            openURLs?(automationURLs)
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let fileURLs = filenames.map { URL(fileURLWithPath: $0) }
        openFiles?(fileURLs, NSWorkspace.shared.frontmostApplication)
        sender.reply(toOpenOrPrint: .success)
    }

    @objc
    func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent _: NSAppleEventDescriptor
    ) {
        guard let value = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue
        else {
            return
        }
        handleURLString(value)
    }

    func handleURLString(_ value: String) {
        guard let url = URL(string: value), !url.isFileURL else {
            return
        }
        if let openURLs {
            openURLs([url])
        } else {
            pendingURLs.append(url)
        }
    }

    private func installVoiceDetectionNotificationController() {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return
        }

        let controller = VoiceDetectionNotificationController { [weak self] action in
            Task { @MainActor in
                self?.handleVoiceDetectionPromptAction(action)
            }
        }
        controller.install(on: .current())
        voiceDetectionNotificationController = controller
    }
}

private enum LuxelSingleInstanceGuard {
    static func exitDuplicateInstanceIfNeeded() {
        guard let existingInstance = existingInstance() else {
            return
        }

        _ = existingInstance.activate()
        Darwin.exit(0)
    }

    private static func existingInstance() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return nil
        }

        let currentProcessIdentifier = NSRunningApplication.current.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { application in
                application.processIdentifier != currentProcessIdentifier && !application.isTerminated
            }
            .sorted { lhs, rhs in
                (lhs.launchDate ?? .distantPast) < (rhs.launchDate ?? .distantPast)
            }
            .first
    }
}
