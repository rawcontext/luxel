import Foundation
import LuxelTestSupport
import Testing

func sharedPackageRootURL(from filePath: String = #filePath) throws -> URL {
    try testPackageRootURL(from: filePath)
}

func sharedFixtureURL(
    _ fileName: String,
    from filePath: String = #filePath
) throws -> URL {
    try testFixtureURL(fileName, from: filePath)
}

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

    func expectSources(
        under directory: URL,
        omit forbiddenSnippets: [String]
    ) throws {
        for fileURL in try swiftFiles(under: directory) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for forbiddenSnippet in forbiddenSnippets {
                #expect(
                    !contents.contains(forbiddenSnippet),
                    "\(fileURL.path) contains \(forbiddenSnippet)"
                )
            }
        }
    }

    func packageRootURL() throws -> URL {
        try sharedPackageRootURL()
    }
}
