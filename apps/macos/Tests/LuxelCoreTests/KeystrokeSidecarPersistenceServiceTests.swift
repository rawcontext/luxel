import Foundation
import LuxelCore
import Testing

@Suite("Keystroke sidecar persistence service")
struct KeystrokeSidecarPersistenceServiceTests {
    @Test("save writes keystroke sidecar and adds manifest entry")
    func saveWritesKeystrokeSidecarAndAddsManifestEntry() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeKeystrokeSidecarFileSystem()
        let service = KeystrokeSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .cursor)
            ])
        )

        let updatedBundle = try service.save(sampleTimeline(), in: bundle)
        let expectedSidecars = [
            try BundleSidecarManifest(kind: .cursor),
            try BundleSidecarManifest(kind: .keystrokes)
        ]

        #expect(updatedBundle.manifest.sidecars == expectedSidecars)
        #expect(
            fileSystem.writtenData.map(\.url) == [
                rootURL.appendingPathComponent("keystrokes.json"),
                rootURL.appendingPathComponent("bundle.json")
            ])

        try expectSavedSidecar(
            KeystrokeSidecarDocument.self,
            expectedDocument: try KeystrokeSidecarDocument(timeline: sampleTimeline()),
            fileSystem: fileSystem,
            updatedBundle: updatedBundle
        )
    }

    @Test("save reuses existing keystroke sidecar file")
    func saveReusesExistingKeystrokeSidecarFile() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = FakeKeystrokeSidecarFileSystem()
        let service = KeystrokeSidecarPersistenceService(fileSystem: fileSystem)
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .keystrokes, fileName: "keyboard-events.json")
        ])
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)

        let updatedBundle = try service.save(sampleTimeline(), in: bundle)

        #expect(updatedBundle == bundle)
        expectWrittenSidecar(
            named: "keyboard-events.json",
            rootURL: rootURL,
            fileSystem: fileSystem
        )
    }

    @Test("load returns nil without keystroke sidecar")
    func loadReturnsNilWithoutKeystrokeSidecar() throws {
        let service = KeystrokeSidecarPersistenceService(fileSystem: FakeKeystrokeSidecarFileSystem())
        let bundle = RecordingBundle(
            rootURL: URL(fileURLWithPath: "/tmp/Luxel Recording"),
            manifest: try BundleManifest()
        )

        #expect(try service.load(from: bundle) == nil)
    }

    @Test("load reads keystroke sidecar document")
    func loadReadsKeystrokeSidecarDocument() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let keystrokeURL = rootURL.appendingPathComponent("keystrokes.json")
        let timeline = try sampleTimeline()
        let document = try KeystrokeSidecarDocument(timeline: timeline)
        let data = try JSONEncoder().encode(document)
        let fileSystem = FakeKeystrokeSidecarFileSystem(readData: [keystrokeURL: data])
        let service = KeystrokeSidecarPersistenceService(fileSystem: fileSystem)
        let bundle = RecordingBundle(
            rootURL: rootURL,
            manifest: try BundleManifest(sidecars: [
                BundleSidecarManifest(kind: .keystrokes)
            ])
        )

        #expect(try service.load(from: bundle) == timeline)
        #expect(fileSystem.readURLs == [keystrokeURL])
    }

    @Test("sidecar document rejects unsupported schema versions")
    func sidecarDocumentRejectsUnsupportedSchemaVersions() throws {
        let data = Data(
            """
            {
              "schemaVersion": 2,
              "timeline": {
                "schemaVersion": 1,
                "events": [],
                "pauses": []
              }
            }
            """.utf8)

        #expect(throws: KeystrokeModelError.unsupportedSidecarSchemaVersion) {
            _ = try JSONDecoder().decode(KeystrokeSidecarDocument.self, from: data)
        }
    }

    private func sampleTimeline() throws -> KeystrokeTimeline {
        try KeystrokeTimeline(
            events: [
                KeystrokeEvent(
                    time: 0.25,
                    kind: .keyDown,
                    keyCode: 8,
                    characters: "c",
                    modifiers: [.command]
                ),
                KeystrokeEvent(
                    time: 0.75,
                    kind: .flagsChanged,
                    keyCode: 55,
                    modifiers: [.command, .shift]
                )
            ],
            pauses: [
                KeystrokePauseInterval(
                    timeRange: TimeRange(start: 1, end: 2),
                    cause: .secureInput
                )
            ]
        )
    }
}

private typealias FakeKeystrokeSidecarFileSystem = SidecarTestFileSystem
