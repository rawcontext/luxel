import AppKit
import Darwin
import LuxelCore
import LuxelPresentation
import SwiftUI

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
        LuxelAppPurchaseGuard.enforce(purchaseGateService: LuxelCompositionRoot.purchaseGateService())
        appDelegate.openFiles = { fileURLs, activationSource in
            guard let fileURL = fileURLs.first else {
                return
            }

            windowPresenter.openEditor(fileURL: fileURL, activationSource: activationSource)
        }
    }

    var body: some Scene {
        LuxelSettingsActionScene(
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

private struct LuxelSettingsActionScene<Content: Scene>: Scene {
    let content: Content

    init(
        windowPresenter: LuxelWindowPresenter,
        openSettingsAction: OpenSettingsAction,
        @SceneBuilder content: () -> Content
    ) {
        windowPresenter.install(openSettingsAction: openSettingsAction)
        self.content = content()
    }

    var body: some Scene {
        content
    }
}

private enum LuxelAppPurchaseGuard {
    static func enforce(purchaseGateService: PurchaseGateService) {
        Task { @MainActor in
            let isEntitled = await purchaseGateService.isEntitled()
            guard !isEntitled else {
                return
            }

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Luxel Purchase Could Not Be Verified"
            alert.informativeText =
                "Install Luxel from the Mac App Store using the Apple Account that purchased it."
            alert.addButton(withTitle: "Quit Luxel")
            alert.runModal()
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
private final class LuxelApplicationDelegate: NSObject, NSApplicationDelegate {
    var openFiles: (([URL], NSRunningApplication?) -> Void)?

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let fileURLs = filenames.map { URL(fileURLWithPath: $0) }
        openFiles?(fileURLs, NSWorkspace.shared.frontmostApplication)
        sender.reply(toOpenOrPrint: .success)
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
