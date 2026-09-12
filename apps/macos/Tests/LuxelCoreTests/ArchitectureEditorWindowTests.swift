import Foundation
import Testing

extension ArchitectureTests {
    @Test("the window presenter is the only app host for the editor")
    func editorHasOneWindowOwner() throws {
        let appDirectory = try packageRootURL().appending(path: "Sources/LuxelApp")
        let editorHosts = try swiftFiles(under: appDirectory).filter { fileURL in
            try String(contentsOf: fileURL, encoding: .utf8).contains("LuxelEditorView(")
        }

        #expect(editorHosts == [appDirectory.appending(path: "App/LuxelWindowPresenter.swift")])
    }
}
