import LuxelPresentation
import SwiftUI

@main
struct LuxelApp: App {
    @State private var model = LuxelMenuModel()
    @State private var editorModel = LuxelEditorModel()
    @State private var cropperPanelController = LuxelCropperPanelController()
    @State private var shortcutController = LuxelShortcutController()

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
