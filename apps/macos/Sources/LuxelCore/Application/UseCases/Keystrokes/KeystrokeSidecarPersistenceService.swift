import Foundation

public struct KeystrokeSidecarPersistenceService: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func save(_ timeline: KeystrokeTimeline, in bundle: RecordingBundle) throws
    -> RecordingBundle {
        let resolvedBundle = try bundleWithKeystrokeSidecar(bundle)
        let sidecarURL = keystrokeSidecarURL(in: resolvedBundle)
        let document = try KeystrokeSidecarDocument(timeline: timeline)
        let data = try makeEncoder().encode(document)

        try fileSystem.writeData(data, to: sidecarURL)

        if resolvedBundle.manifest != bundle.manifest {
            try persistManifest(resolvedBundle.manifest, for: resolvedBundle.rootURL)
        }

        return resolvedBundle
    }

    public func load(from bundle: RecordingBundle) throws -> KeystrokeTimeline? {
        guard let sidecarURL = bundle.sidecarURL(for: .keystrokes) else {
            return nil
        }

        let data = try fileSystem.readData(at: sidecarURL)
        return try JSONDecoder().decode(KeystrokeSidecarDocument.self, from: data).timeline
    }

    private func bundleWithKeystrokeSidecar(_ bundle: RecordingBundle) throws -> RecordingBundle {
        if bundle.manifest.sidecar(for: .keystrokes) != nil {
            return bundle
        }

        let manifest = try BundleManifest(
            schemaVersion: bundle.manifest.schemaVersion,
            primaryFileName: bundle.manifest.primaryFileName,
            sidecars: bundle.manifest.sidecars + [BundleSidecarManifest(kind: .keystrokes)]
        )
        return RecordingBundle(rootURL: bundle.rootURL, manifest: manifest)
    }

    private func keystrokeSidecarURL(in bundle: RecordingBundle) -> URL {
        bundle.sidecarURL(for: .keystrokes)!
    }

    private func persistManifest(_ manifest: BundleManifest, for rootURL: URL) throws {
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)
        let data = try makeEncoder().encode(manifest)
        try fileSystem.writeData(data, to: bundle.manifestURL)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
