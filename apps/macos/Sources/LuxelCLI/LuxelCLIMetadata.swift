import Foundation
import LuxelCore

enum LuxelCLIMetadata {
    static let current = read()

    static var versionSummary: String {
        current.versionSummary
    }

    private static func read() -> AppMetadata {
        let bundleMetadata = BundleAppMetadataReader().read()
        if bundleMetadata.version != "0.0.0" || !bundleMetadata.build.isEmpty {
            return bundleMetadata
        }

        for url in candidateInfoPlistURLs() {
            if let metadata = readInfoPlist(at: url) {
                return metadata
            }
        }

        return bundleMetadata
    }

    private static func candidateInfoPlistURLs() -> [URL] {
        var urls: [URL] = []

        if let executableURL = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            urls.append(
                executableURL
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Info.plist")
            )
            urls.append(contentsOf: packageInfoPlistURLs(startingAt: executableURL))
        }

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(contentsOf: packageInfoPlistURLs(startingAt: workingDirectory))

        return unique(urls)
    }

    private static func packageInfoPlistURLs(startingAt startURL: URL) -> [URL] {
        var directory = startURL.hasDirectoryPath ? startURL : startURL.deletingLastPathComponent()
        var urls: [URL] = []

        for _ in 0..<12 {
            urls.append(directory.appendingPathComponent("Configuration/Luxel/Info.plist"))
            urls.append(directory.appendingPathComponent("apps/macos/Configuration/Luxel/Info.plist"))

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                break
            }
            directory = parent
        }

        return urls
    }

    private static func readInfoPlist(at url: URL) -> AppMetadata? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }

        let stringDictionary = dictionary.compactMapValues { $0 as? String }
        let metadata = BundleAppMetadataReader(infoDictionary: stringDictionary).read()
        guard metadata.version != "0.0.0" || !metadata.build.isEmpty else {
            return nil
        }

        return metadata
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []
        var uniqueURLs: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard seenPaths.insert(path).inserted else {
                continue
            }
            uniqueURLs.append(url)
        }
        return uniqueURLs
    }
}
