import Foundation
import LuxelCore
import Testing

@Suite("Cursor sidecar persistence service")
struct CursorSidecarPersistenceServiceTests {
    @Test("save writes cursor sidecar and adds manifest entry")
    func saveWritesCursorSidecarAndAddsManifestEntry() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeCursorSidecarFileSystem()
        let service = CursorSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .captions)
            ])
        )

        let updatedBundle = try service.save(sampleTimeline(), in: bundle)
        let expectedSidecars = [
            try BundleSidecarManifest(kind: .captions),
            try BundleSidecarManifest(kind: .cursor)
        ]

        #expect(updatedBundle.manifest.sidecars == expectedSidecars)
        #expect(
            fileSystem.writtenData.map(\.url) == [
                rootURL.appendingPathComponent("cursor.json"),
                rootURL.appendingPathComponent("bundle.json")
            ])

        try expectSavedSidecar(
            CursorSidecarDocument.self,
            expectedDocument: try CursorSidecarDocument(timeline: sampleTimeline()),
            fileSystem: fileSystem,
            updatedBundle: updatedBundle
        )
    }

    @Test("save reuses existing cursor sidecar file")
    func saveReusesExistingCursorSidecarFile() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeCursorSidecarFileSystem()
        let service = CursorSidecarPersistenceService(fileSystem: fileSystem)
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .cursor, fileName: "pointer-events.json")
        ])
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)

        let updatedBundle = try service.save(sampleTimeline(), in: bundle)

        #expect(updatedBundle == bundle)
        expectWrittenSidecar(
            named: "pointer-events.json",
            rootURL: rootURL,
            fileSystem: fileSystem
        )
    }

    @Test("load returns nil without cursor sidecar")
    func loadReturnsNilWithoutCursorSidecar() throws {
        let service = CursorSidecarPersistenceService(fileSystem: FakeCursorSidecarFileSystem())
        let bundle = RecordingBundle(
            rootURL: URL(fileURLWithPath: "/tmp/Luxel Recording"),
            manifest: try BundleManifest()
        )

        #expect(try service.load(from: bundle) == nil)
    }

    @Test("load reads cursor sidecar document")
    func loadReadsCursorSidecarDocument() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let cursorURL = rootURL.appendingPathComponent("cursor.json")
        let timeline = try sampleTimeline()
        let document = try CursorSidecarDocument(timeline: timeline)
        let data = try JSONEncoder().encode(document)
        let fileSystem = FakeCursorSidecarFileSystem(readData: [cursorURL: data])
        let service = CursorSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .cursor)
            ])
        )

        #expect(try service.load(from: bundle) == timeline)
        #expect(fileSystem.readURLs == [cursorURL])
    }

    @Test("sidecar document rejects unsupported schema versions")
    func sidecarDocumentRejectsUnsupportedSchemaVersions() throws {
        let data = Data(
            """
      {
        "schemaVersion": 2,
        "timeline": {
          "schemaVersion": 1,
          "samples": [],
          "clicks": [],
          "spotlightToggles": [],
          "cursorImages": []
        }
      }
      """.utf8)

        #expect(throws: CursorEffectModelError.unsupportedSidecarSchemaVersion) {
            _ = try JSONDecoder().decode(CursorSidecarDocument.self, from: data)
        }
    }

    private func sampleTimeline() throws -> CursorTimeline {
        let image = try CursorImageAsset(
            id: "arrow",
            pngData: Data([0x89, 0x50, 0x4e, 0x47]),
            hotspot: CursorPoint(x: 2, y: 3),
            scale: 2
        )

        return try CursorTimeline(
            samples: [
                CursorSample(
                    time: 0.25,
                    position: CursorPoint(x: 10, y: 20),
                    cursorImageID: image.id
                )
            ],
            clicks: [
                CursorClickEvent(time: 0.5, button: .left, phase: .down)
            ],
            spotlightToggles: [0.75],
            cursorImages: [image]
        )
    }
}

private typealias FakeCursorSidecarFileSystem = SidecarTestFileSystem
