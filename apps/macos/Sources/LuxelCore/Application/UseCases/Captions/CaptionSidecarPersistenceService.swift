import Foundation

public struct CaptionSidecarPersistenceService: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func save(_ track: CaptionTrack, in bundle: RecordingBundle) throws -> RecordingBundle {
        let resolvedBundle = try bundleWithCaptionsSidecar(bundle)
        let sidecarURL = captionSidecarURL(in: resolvedBundle)
        let document = try CaptionSidecarDocument(track: track)
        let data = try makeEncoder().encode(document)

        try fileSystem.writeData(data, to: sidecarURL)

        if resolvedBundle.manifest != bundle.manifest {
            try persistManifest(resolvedBundle.manifest, for: resolvedBundle.rootURL)
        }

        return resolvedBundle
    }

    public func load(from bundle: RecordingBundle) throws -> CaptionTrack? {
        guard let sidecarURL = bundle.sidecarURL(for: .captions) else {
            return nil
        }

        let data = try fileSystem.readData(at: sidecarURL)
        return try JSONDecoder().decode(CaptionSidecarDocument.self, from: data).track
    }

    private func bundleWithCaptionsSidecar(_ bundle: RecordingBundle) throws -> RecordingBundle {
        if bundle.manifest.sidecar(for: .captions) != nil {
            return bundle
        }

        let manifest = try BundleManifest(
            schemaVersion: bundle.manifest.schemaVersion,
            primaryFileName: bundle.manifest.primaryFileName,
            sidecars: bundle.manifest.sidecars + [BundleSidecarManifest(kind: .captions)]
        )
        return RecordingBundle(rootURL: bundle.rootURL, manifest: manifest)
    }

    private func captionSidecarURL(in bundle: RecordingBundle) -> URL {
        bundle.sidecarURL(for: .captions)!
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
