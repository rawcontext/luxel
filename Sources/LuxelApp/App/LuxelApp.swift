import LuxelPresentation
import SwiftUI

@main
struct LuxelApp: App {
    @State private var model: LuxelMenuModel
    @State private var editorModel = LuxelEditorModel()
    @State private var cropperPanelController: LuxelCropperPanelController
    @State private var shortcutController = LuxelShortcutController()

    init() {
        let captureTargetCatalog = LuxelCompositionRoot.captureTargetCatalog()
        let captureTargetService = LuxelCompositionRoot.captureTargetService(catalog: captureTargetCatalog)

        _model = State(initialValue: LuxelMenuModel(captureTargetService: captureTargetService))
        _cropperPanelController = State(initialValue: LuxelCropperPanelController(
            targetService: captureTargetService
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            LuxelMenu(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController
            )
        } label: {
            LuxelMenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: LuxelEditorScene.id) {
            LuxelEditorView(model: editorModel)
        }
        .commands {
            LuxelEditorCommands()
        }

        Settings {
            LuxelSettingsView(
                model: model,
                editorModel: editorModel,
                cropperPanelController: cropperPanelController,
                shortcutController: shortcutController
            )
        }
    }
}
