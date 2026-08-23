import Foundation

public enum KeystrokeSidecarRemovalMode: Sendable {
    case delete
    case trash
}

public struct KeystrokeSidecarRemovalResult: Equatable, Sendable {
    public let updatedBundleManifest: BundleManifest?

    public init(updatedBundleManifest: BundleManifest?) {
        self.updatedBundleManifest = updatedBundleManifest
    }
}

public struct KeystrokeSidecarRemovalService: Sendable {
    private let fileSystem: any FileSystem
    private let mode: KeystrokeSidecarRemovalMode

    public init(fileSystem: any FileSystem, mode: KeystrokeSidecarRemovalMode) {
        self.fileSystem = fileSystem
        self.mode = mode
    }

    public func remove(
        nextTo mediaURL: URL,
        bundle knownBundle: RecordingBundle? = nil
    ) throws -> KeystrokeSidecarRemovalResult {
        let bundle = try knownBundle ?? discoveredBundle(for: mediaURL)
        let siblingURL = KeystrokeSidecarDocument.sidecarURL(nextTo: mediaURL)

        guard let bundle,
            let bundleSidecarURL = bundle.sidecarURL(for: .keystrokes)
        else {
            try removeIfPresent(siblingURL)
            return KeystrokeSidecarRemovalResult(updatedBundleManifest: nil)
        }

        let updatedManifest = try bundle.manifest.filteringSidecars { $0.kind != .keystrokes }
        try persistManifest(updatedManifest, for: bundle.rootURL)
        do {
            try removeIfPresent(bundleSidecarURL)
            if siblingURL != bundleSidecarURL {
                try removeIfPresent(siblingURL)
            }
        } catch {
            try? persistManifest(bundle.manifest, for: bundle.rootURL)
            throw error
        }
        return KeystrokeSidecarRemovalResult(updatedBundleManifest: updatedManifest)
    }

    private func discoveredBundle(for mediaURL: URL) throws -> RecordingBundle? {
        let rootURL = mediaURL.deletingLastPathComponent()
        let manifestURL = rootURL.appendingPathComponent(BundleManifest.fileName)
        guard fileSystem.fileExists(at: manifestURL) else {
            return nil
        }
        let manifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: fileSystem.readData(at: manifestURL)
        )
        guard manifest.primaryFileName == mediaURL.lastPathComponent else {
            return nil
        }
        return RecordingBundle(rootURL: rootURL, manifest: manifest)
    }

    private func persistManifest(_ manifest: BundleManifest, for rootURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileSystem.writeData(
            encoder.encode(manifest),
            to: rootURL.appendingPathComponent(BundleManifest.fileName)
        )
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileSystem.fileExists(at: url) else {
            return
        }
        switch mode {
        case .delete:
            try fileSystem.removeFile(at: url)
        case .trash:
            try fileSystem.trashItem(at: url)
        }
    }
}
