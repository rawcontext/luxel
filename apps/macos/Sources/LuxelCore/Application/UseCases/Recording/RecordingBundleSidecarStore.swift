import Foundation

struct RecordingBundleSidecarStore: Sendable {
    private let fileSystem: any FileSystem

    init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    func save<Document: Encodable>(
        _ document: Document,
        kind: SidecarKind,
        in bundle: RecordingBundle
    ) throws -> RecordingBundle {
        let resolvedBundle = try addingSidecar(kind, to: bundle)
        guard let sidecarURL = resolvedBundle.sidecarURL(for: kind) else {
            return resolvedBundle
        }

        try fileSystem.writeData(makeEncoder().encode(document), to: sidecarURL)
        if resolvedBundle.manifest != bundle.manifest {
            try persistManifest(resolvedBundle.manifest, for: resolvedBundle.rootURL)
        }
        return resolvedBundle
    }

    func load<Document: Decodable>(
        _ documentType: Document.Type,
        kind: SidecarKind,
        from bundle: RecordingBundle
    ) throws -> Document? {
        guard let sidecarURL = bundle.sidecarURL(for: kind) else {
            return nil
        }

        let data = try fileSystem.readData(at: sidecarURL)
        return try JSONDecoder().decode(documentType, from: data)
    }

    private func addingSidecar(
        _ kind: SidecarKind,
        to bundle: RecordingBundle
    ) throws -> RecordingBundle {
        guard bundle.manifest.sidecar(for: kind) == nil else {
            return bundle
        }

        let manifest = try BundleManifest(
            schemaVersion: bundle.manifest.schemaVersion,
            primaryFileName: bundle.manifest.primaryFileName,
            sidecars: bundle.manifest.sidecars + [BundleSidecarManifest(kind: kind)]
        )
        return RecordingBundle(rootURL: bundle.rootURL, manifest: manifest)
    }

    private func persistManifest(_ manifest: BundleManifest, for rootURL: URL) throws {
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)
        try fileSystem.writeData(makeEncoder().encode(manifest), to: bundle.manifestURL)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
