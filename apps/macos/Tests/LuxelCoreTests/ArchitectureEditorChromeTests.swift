import Foundation
import Testing

extension ArchitectureTests {
    @Test("editor inspector hides the automatic top scroll-edge shadow")
    func editorInspectorHidesTopScrollEdgeShadow() throws {
        let source = try sourceText(for: [
            "Sources/LuxelPresentation/Editor/Views/LuxelEditorView.swift"
        ])

        #expect(source.contains(".scrollEdgeEffectHidden(true, for: .top)"))
    }
}
