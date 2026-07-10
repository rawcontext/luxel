import Foundation
import Testing

extension ArchitectureTests {
    func swiftFiles(under directory: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
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

    func sourceContents(under directory: URL) throws -> String {
        try swiftFiles(under: directory)
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    func sourceText(for paths: [String], encoding: String.Encoding = .utf8) throws -> String {
        let packageRoot = try packageRootURL()
        return
            try paths
            .map { try String(contentsOf: packageRoot.appending(path: $0), encoding: encoding) }
            .joined(separator: "\n")
    }

    func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
