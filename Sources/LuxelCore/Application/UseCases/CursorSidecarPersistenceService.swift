import Foundation

public struct CursorSidecarPersistenceService: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func save(_ timeline: CursorTimeline, in bundle: RecordingBundle) throws -> RecordingBundle {
        let resolvedBundle = try bundleWithCursorSidecar(bundle)
        let sidecarURL = cursorSidecarURL(in: resolvedBundle)
        let document = try CursorSidecarDocument(timeline: timeline)
        let data = try makeEncoder().encode(document)

        try fileSystem.writeData(data, to: sidecarURL)

        if resolvedBundle.manifest != bundle.manifest {
            try persistManifest(resolvedBundle.manifest, for: resolvedBundle.rootURL)
        }

        return resolvedBundle
    }

    public func load(from bundle: RecordingBundle) throws -> CursorTimeline? {
        guard let sidecarURL = bundle.sidecarURL(for: .cursor) else {
            return nil
        }

        let data = try fileSystem.readData(at: sidecarURL)
        return try JSONDecoder().decode(CursorSidecarDocument.self, from: data).timeline
    }

    private func bundleWithCursorSidecar(_ bundle: RecordingBundle) throws -> RecordingBundle {
        if bundle.manifest.sidecar(for: .cursor) != nil {
            return bundle
        }

        let manifest = try BundleManifest(
            schemaVersion: bundle.manifest.schemaVersion,
            primaryFileName: bundle.manifest.primaryFileName,
            sidecars: bundle.manifest.sidecars + [BundleSidecarManifest(kind: .cursor)]
        )
        return RecordingBundle(rootURL: bundle.rootURL, manifest: manifest)
    }

    private func cursorSidecarURL(in bundle: RecordingBundle) -> URL {
        bundle.sidecarURL(for: .cursor)!
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
