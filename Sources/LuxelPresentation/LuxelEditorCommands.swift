import SwiftUI

@MainActor
struct LuxelEditorCommandContext {
    let canUndo: Bool
    let canRedo: Bool
    let canDiscard: Bool
    let undo: @MainActor () -> Void
    let redo: @MainActor () -> Void
    let discard: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var luxelEditorCommandContext: LuxelEditorCommandContext?
}

public struct LuxelEditorCommands: Commands {
    @FocusedValue(\.luxelEditorCommandContext) private var context

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                context?.undo()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(context?.canUndo != true)

            Button("Redo") {
                context?.redo()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(context?.canRedo != true)
        }

        CommandGroup(after: .undoRedo) {
            Divider()

            Button("Discard Recording") {
                context?.discard()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(context?.canDiscard != true)
        }
    }
}
