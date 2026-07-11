import Foundation
import LuxelCore
import Testing

@Suite("Keystroke sidecar file loader")
struct KeystrokeSidecarFileLoaderTests {
    @Test("loads sibling sidecar and bundle sidecar")
    func loadsSiblingAndBundleSidecars() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let timeline = try KeystrokeTimeline(events: [
            KeystrokeEvent(time: 0.25, kind: .keyDown, keyCode: 0, characters: "a")
        ])
        let data = try JSONEncoder().encode(KeystrokeSidecarDocument(timeline: timeline))
        let siblingMedia = temporaryDirectory.appendingPathComponent("capture.mp4")
        let siblingURL = KeystrokeSidecarDocument.sidecarURL(nextTo: siblingMedia)
        try data.write(to: siblingURL)

        let loader = KeystrokeSidecarFileLoader()
        #expect(try loader.load(nextTo: siblingMedia) == timeline)

        let bundleDirectory = temporaryDirectory.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(
            at: bundleDirectory,
            withIntermediateDirectories: true
        )
        let bundleMedia = bundleDirectory.appendingPathComponent("screen.mov")
        let manifest = try BundleManifest(sidecars: [BundleSidecarManifest(kind: .keystrokes)])
        try JSONEncoder().encode(manifest).write(
            to: bundleDirectory.appendingPathComponent(BundleManifest.fileName)
        )
        try data.write(to: bundleDirectory.appendingPathComponent("keystrokes.json"))

        #expect(try loader.load(nextTo: bundleMedia) == timeline)
    }

    @Test("removing bundle keystrokes clears the persisted manifest and loader")
    func removingBundleKeystrokesClearsManifestAndLoader() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .keystrokes),
            BundleSidecarManifest(kind: .captions)
        ])
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)
        FileManager.default.createFile(atPath: bundle.primaryURL.path, contents: Data())
        FileManager.default.createFile(
            atPath: try #require(bundle.sidecarURL(for: .keystrokes)).path,
            contents: try JSONEncoder().encode(
                KeystrokeSidecarDocument(timeline: KeystrokeTimeline())
            )
        )
        try JSONEncoder().encode(manifest).write(to: bundle.manifestURL, options: .atomic)
        let recording = PastRecording(
            fileURL: rootURL,
            name: "Bundle",
            date: Date(),
            bundleManifest: manifest
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = RecordingHistoryService(
            store: store,
            fileSystem: KeystrokeRemovalFileSystem(),
            dateProvider: SystemDateProvider(),
            mediaProbe: StaticMediaProbe(result: .playable)
        )

        try service.removeKeystrokeData(from: recording)

        #expect(try KeystrokeSidecarFileLoader().load(nextTo: bundle.primaryURL) == nil)
        let persistedManifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(contentsOf: bundle.manifestURL)
        )
        #expect(persistedManifest.sidecar(for: .keystrokes) == nil)
        #expect(persistedManifest.sidecar(for: .captions) != nil)
        #expect(store.recordings.first?.bundleManifest == persistedManifest)
    }
}

private struct KeystrokeRemovalFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    func writeData(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func removeFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
