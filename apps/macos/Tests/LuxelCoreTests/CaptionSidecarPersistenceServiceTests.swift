import Foundation
import LuxelCore
import Testing

@Suite("Caption sidecar persistence service")
struct CaptionSidecarPersistenceServiceTests {
    @Test("save writes captions sidecar and adds manifest entry")
    func saveWritesCaptionsSidecarAndAddsManifestEntry() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeCaptionSidecarFileSystem()
        let service = CaptionSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .cursor)
            ])
        )

        let updatedBundle = try service.save(sampleTrack(), in: bundle)
        let expectedSidecars = [
            try BundleSidecarManifest(kind: .cursor),
            try BundleSidecarManifest(kind: .captions)
        ]

        #expect(updatedBundle.manifest.sidecars == expectedSidecars)
        #expect(
            fileSystem.writtenData.map(\.url) == [
                rootURL.appendingPathComponent("captions.json"),
                rootURL.appendingPathComponent("bundle.json")
            ])

        try expectSavedSidecar(
            CaptionSidecarDocument.self,
            expectedDocument: try CaptionSidecarDocument(track: sampleTrack()),
            fileSystem: fileSystem,
            updatedBundle: updatedBundle
        )
    }

    @Test("save reuses existing captions sidecar file")
    func saveReusesExistingCaptionsSidecarFile() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeCaptionSidecarFileSystem()
        let service = CaptionSidecarPersistenceService(fileSystem: fileSystem)
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .captions, fileName: "reviewed-captions.json")
        ])
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)

        let updatedBundle = try service.save(sampleTrack(), in: bundle)

        #expect(updatedBundle == bundle)
        expectWrittenSidecar(
            named: "reviewed-captions.json",
            rootURL: rootURL,
            fileSystem: fileSystem
        )
    }

    @Test("load returns nil without captions sidecar")
    func loadReturnsNilWithoutCaptionsSidecar() throws {
        let service = CaptionSidecarPersistenceService(fileSystem: FakeCaptionSidecarFileSystem())
        let bundle = RecordingBundle(
            rootURL: URL(fileURLWithPath: "/tmp/Luxel Recording"),
            manifest: try BundleManifest()
        )

        #expect(try service.load(from: bundle) == nil)
    }

    @Test("load reads captions sidecar document")
    func loadReadsCaptionsSidecarDocument() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let captionURL = rootURL.appendingPathComponent("captions.json")
        let track = try sampleTrack()
        let document = try CaptionSidecarDocument(track: track)
        let data = try JSONEncoder().encode(document)
        let fileSystem = FakeCaptionSidecarFileSystem(readData: [captionURL: data])
        let service = CaptionSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .captions)
            ])
        )

        #expect(try service.load(from: bundle) == track)
        #expect(fileSystem.readURLs == [captionURL])
    }

    @Test("sidecar document rejects unsupported schema versions")
    func sidecarDocumentRejectsUnsupportedSchemaVersions() throws {
        let data = Data(
            """
      {
        "schemaVersion": 2,
        "track": {
          "cues": [],
          "language": "en"
        }
      }
      """.utf8)

        #expect(throws: CaptionModelError.unsupportedSidecarSchemaVersion) {
            _ = try JSONDecoder().decode(CaptionSidecarDocument.self, from: data)
        }
    }

    private func sampleTrack() throws -> CaptionTrack {
        try CaptionTrack(
            cues: [
                try CaptionCue(timeRange: TimeRange(start: 1, end: 2.5), text: "Hello")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .microphone
        )
    }
}

private typealias FakeCaptionSidecarFileSystem = SidecarTestFileSystem
