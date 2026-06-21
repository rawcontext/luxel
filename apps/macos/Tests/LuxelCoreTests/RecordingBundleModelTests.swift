import Foundation
import LuxelCore
import Testing

@Suite("Recording bundle models")
struct RecordingBundleModelTests {
    @Test("sidecar kinds expose default bundle file names")
    func sidecarKindsExposeDefaultBundleFileNames() {
        #expect(SidecarKind.camera.defaultFileName == "camera.mov")
        #expect(SidecarKind.cursor.defaultFileName == "cursor.json")
        #expect(SidecarKind.keystrokes.defaultFileName == "keystrokes.json")
        #expect(SidecarKind.captions.defaultFileName == "captions.json")
    }

    @Test("manifest stores primary file and sidecar inventory")
    func manifestStoresPrimaryFileAndSidecarInventory() throws {
        let camera = try BundleSidecarManifest(kind: .camera, syncOffsetMilliseconds: 33)
        let cursor = try BundleSidecarManifest(kind: .cursor)

        let manifest = try BundleManifest(sidecars: [camera, cursor])

        #expect(manifest.schemaVersion == BundleManifest.currentSchemaVersion)
        #expect(manifest.primaryFileName == "screen.mov")
        #expect(manifest.sidecars == [camera, cursor])
        #expect(manifest.sidecar(for: .camera) == camera)
        #expect(manifest.sidecar(for: .captions) == nil)
    }

    @Test("manifest rejects invalid file names")
    func manifestRejectsInvalidFileNames() throws {
        #expect(throws: RecordingBundleError.invalidBundleFileName) {
            _ = try BundleManifest(primaryFileName: "")
        }
        #expect(throws: RecordingBundleError.invalidBundleFileName) {
            _ = try BundleManifest(primaryFileName: "tracks/screen.mov")
        }
        #expect(throws: RecordingBundleError.invalidBundleFileName) {
            _ = try BundleSidecarManifest(kind: .captions, fileName: "..")
        }
        #expect(throws: RecordingBundleError.unsupportedSchemaVersion) {
            _ = try BundleManifest(schemaVersion: 2)
        }
    }

    @Test("manifest rejects duplicate sidecar kinds and file names")
    func manifestRejectsDuplicateSidecarKindsAndFileNames() throws {
        let camera = try BundleSidecarManifest(kind: .camera)
        let duplicateCamera = try BundleSidecarManifest(kind: .camera, fileName: "camera-copy.mov")
        let cursorWithCameraFile = try BundleSidecarManifest(kind: .cursor, fileName: "camera.mov")
        let cursorWithPrimaryFile = try BundleSidecarManifest(kind: .cursor, fileName: "screen.mov")

        #expect(throws: RecordingBundleError.duplicateSidecarKind) {
            _ = try BundleManifest(sidecars: [camera, duplicateCamera])
        }
        #expect(throws: RecordingBundleError.duplicateBundleFileName) {
            _ = try BundleManifest(sidecars: [camera, cursorWithCameraFile])
        }
        #expect(throws: RecordingBundleError.duplicateBundleFileName) {
            _ = try BundleManifest(sidecars: [cursorWithPrimaryFile])
        }
    }

    @Test("bundle resolves primary manifest and sidecar URLs from root")
    func bundleResolvesURLsFromRoot() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .camera, syncOffsetMilliseconds: -12),
            BundleSidecarManifest(kind: .captions)
        ])

        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)

        #expect(bundle.primaryURL == rootURL.appendingPathComponent("screen.mov"))
        #expect(bundle.manifestURL == rootURL.appendingPathComponent("bundle.json"))
        #expect(bundle.sidecarURL(for: .camera) == rootURL.appendingPathComponent("camera.mov"))
        #expect(bundle.sidecarURL(for: .captions) == rootURL.appendingPathComponent("captions.json"))
        #expect(bundle.sidecarURL(for: .cursor) == nil)
        #expect(
            bundle.sidecars == [
                .camera: rootURL.appendingPathComponent("camera.mov"),
                .captions: rootURL.appendingPathComponent("captions.json")
            ])
    }

    @Test("manifest round trips through JSON")
    func manifestRoundTripsThroughJSON() throws {
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .camera, syncOffsetMilliseconds: 42),
            BundleSidecarManifest(kind: .keystrokes),
            BundleSidecarManifest(kind: .captions)
        ])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(BundleManifest.self, from: data)

        #expect(decoded == manifest)
    }

    @Test("manifest filters sidecars while preserving primary file")
    func manifestFiltersSidecars() throws {
        let manifest = try BundleManifest(
            primaryFileName: "primary.mp4",
            sidecars: [
                BundleSidecarManifest(kind: .camera),
                BundleSidecarManifest(kind: .captions)
            ]
        )

        let filtered = try manifest.filteringSidecars { $0.kind == .captions }

        #expect(filtered.primaryFileName == "primary.mp4")
        #expect(filtered.sidecars == [try BundleSidecarManifest(kind: .captions)])
    }
}
