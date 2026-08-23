import Foundation

public struct KeystrokeSidecarFileLoader: Sendable {
    public init() {}

    public func load(nextTo mediaURL: URL) throws -> KeystrokeTimeline? {
        let siblingURL = KeystrokeSidecarDocument.sidecarURL(nextTo: mediaURL)
        if FileManager.default.fileExists(atPath: siblingURL.path) {
            return try decode(at: siblingURL)
        }

        let manifestURL = mediaURL.deletingLastPathComponent()
            .appendingPathComponent(BundleManifest.fileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let manifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.primaryFileName == mediaURL.lastPathComponent,
            let sidecar = manifest.sidecar(for: .keystrokes)
        else {
            return nil
        }
        return try decode(
            at: mediaURL.deletingLastPathComponent().appendingPathComponent(sidecar.fileName)
        )
    }

    public func sidecarURL(nextTo mediaURL: URL) -> URL? {
        let siblingURL = KeystrokeSidecarDocument.sidecarURL(nextTo: mediaURL)
        if FileManager.default.fileExists(atPath: siblingURL.path) {
            return siblingURL
        }

        let manifestURL = mediaURL.deletingLastPathComponent()
            .appendingPathComponent(BundleManifest.fileName)
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(BundleManifest.self, from: data),
            manifest.primaryFileName == mediaURL.lastPathComponent,
            let sidecar = manifest.sidecar(for: .keystrokes)
        else {
            return nil
        }
        let sidecarURL = mediaURL.deletingLastPathComponent()
            .appendingPathComponent(sidecar.fileName)
        return FileManager.default.fileExists(atPath: sidecarURL.path) ? sidecarURL : nil
    }

    private func decode(at url: URL) throws -> KeystrokeTimeline {
        try JSONDecoder().decode(
            KeystrokeSidecarDocument.self,
            from: Data(contentsOf: url)
        ).timeline
    }
}
