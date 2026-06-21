import AppKit
import Darwin
import LuxelCore
import LuxelPresentation
import SwiftUI

@main
struct LuxelApp: App {
    @State private var model: LuxelMenuModel
    @State private var editorModel: LuxelEditorModel
    @State private var cropperPanelController: LuxelCropperPanelController
    @State private var shortcutController: LuxelShortcutController
    @State private var windowPresenter: LuxelWindowPresenter
    @State private var statusItemController: LuxelStatusItemController

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
            errorReporter: errorReporter
        )
        let editorModel = LuxelCompositionRoot.editorModel(errorReporter: errorReporter)
        let cropperPanelController = LuxelCropperPanelController(
            targetService: captureTargetService,
            exclusionRegistry: captureExclusionRegistry
        )
        let shortcutController = LuxelShortcutController()
        let windowPresenter = LuxelWindowPresenter(
            model: model,
            editorModel: editorModel,
            cropperPanelController: cropperPanelController,
            shortcutController: shortcutController
        )

        _model = State(initialValue: model)
        _editorModel = State(initialValue: editorModel)
        _cropperPanelController = State(initialValue: cropperPanelController)
        _shortcutController = State(initialValue: shortcutController)
        _windowPresenter = State(initialValue: windowPresenter)
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
        WindowGroup(id: LuxelEditorScene.id) {
            LuxelEditorView(model: editorModel)
        }
        .defaultLaunchBehavior(.suppressed)

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
        }
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
