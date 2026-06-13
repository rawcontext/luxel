import Foundation
import Testing

@Suite("Architecture rules")
struct ArchitectureTests {
    @Test("Domain and application do not import macOS framework adapters")
    func coreLayersDoNotImportOuterFrameworks() throws {
        let packageRoot = try packageRootURL()
        let checkedDirectories = [
            packageRoot.appending(path: "Sources/LuxelCore/Domain"),
            packageRoot.appending(path: "Sources/LuxelCore/Application")
        ]
        let forbiddenImports = [
            "import AppKit",
            "import SwiftUI",
            "import ScreenCaptureKit",
            "import AVFoundation",
            "import AVKit",
            "import ImageIO",
            "import VideoToolbox",
            "import ServiceManagement"
        ]

        for directory in checkedDirectories {
            for fileURL in try swiftFiles(under: directory) {
                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for forbiddenImport in forbiddenImports {
                    #expect(!contents.contains(forbiddenImport), "\(fileURL.path) contains \(forbiddenImport)")
                }
            }
        }
    }

    private func swiftFiles(under directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            let url = try #require(item as? URL)
            guard url.pathExtension == "swift" else {
                return nil
            }

            return url
        }
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
