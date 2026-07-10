import Foundation
import LuxelCore
import Testing

extension RecordingHistoryTests {
    @Test("getPastRecordings filters missing files and persists the filtered list")
    func getPastRecordingsFiltersMissingFiles() {
        let existingURL = URL(fileURLWithPath: "/tmp/existing.mp4")
        let missingURL = URL(fileURLWithPath: "/tmp/missing.mp4")
        let store = InMemoryRecordingHistoryStore(recordings: [
            PastRecording(fileURL: existingURL, name: "Existing", date: Date(timeIntervalSince1970: 1)),
            PastRecording(fileURL: missingURL, name: "Missing", date: Date(timeIntervalSince1970: 2))
        ])
        let service = makeService(store: store, existingFiles: [existingURL])

        let recordings = service.getPastRecordings()

        #expect(
            recordings == [
                PastRecording(fileURL: existingURL, name: "Existing", date: Date(timeIntervalSince1970: 1))
            ])
        #expect(store.recordings == recordings)
    }

    @Test("getPastRecordings keeps bundle root when primary media exists")
    func getPastRecordingsKeepsBundleRootWhenPrimaryMediaExists() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let cameraURL = rootURL.appendingPathComponent("camera.mov")
        let cursorURL = rootURL.appendingPathComponent("cursor.json")
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .camera),
            BundleSidecarManifest(kind: .cursor)
        ])
        let recording = PastRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: Date(timeIntervalSince1970: 2),
            bundleManifest: manifest
        )
        let service = makeService(
            store: InMemoryRecordingHistoryStore(recordings: [recording]),
            existingFiles: [rootURL, rootURL.appendingPathComponent("screen.mov"), cameraURL, cursorURL]
        )

        let recordings = service.getPastRecordings()
        #expect(recordings == [recording])
        #expect(recordings.first?.primaryMediaURL == rootURL.appendingPathComponent("screen.mov"))
    }

    @Test("getPastRecordings drops missing bundle sidecars with diagnostics")
    func getPastRecordingsDropsMissingBundleSidecarsWithDiagnostics() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let camera = try BundleSidecarManifest(kind: .camera)
        let cursor = try BundleSidecarManifest(kind: .cursor)
        let manifest = try BundleManifest(sidecars: [camera, cursor])
        let sanitizedManifest = try BundleManifest(sidecars: [camera])
        let recording = PastRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: Date(timeIntervalSince1970: 2),
            bundleManifest: manifest
        )
        let fileSystem = RecordingHistoryFakeFileSystem(existingFiles: [
            rootURL,
            rootURL.appendingPathComponent("screen.mov"),
            rootURL.appendingPathComponent("camera.mov")
        ])
        let diagnosticClient = RecordingHistoryDiagnosticSpy()
        let service = makeService(
            store: InMemoryRecordingHistoryStore(recordings: [recording]),
            fileSystem: fileSystem,
            now: Date(timeIntervalSince1970: 10),
            diagnosticClient: diagnosticClient
        )

        let recordings = service.getPastRecordings()

        let expected = recording.replacingBundleManifest(sanitizedManifest)
        #expect(recordings == [expected])
        #expect(
            diagnosticClient.diagnostics == [
                CorruptRecordingDiagnostic(
                    fileURL: rootURL.appendingPathComponent("cursor.json"),
                    reason: "Missing bundle sidecar",
                    recordedAt: Date(timeIntervalSince1970: 10)
                )
            ])
        #expect(fileSystem.writtenData.map(\.url) == [rootURL.appendingPathComponent("bundle.json")])
        let persistedManifest = try JSONDecoder().decode(
            BundleManifest.self, from: try #require(fileSystem.writtenData.first?.data))
        #expect(persistedManifest == sanitizedManifest)
    }

    @Test("getPastRecordings prunes bundle roots with missing primary media")
    func getPastRecordingsPrunesBundleRootsWithMissingPrimaryMedia() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let recording = PastRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: Date(timeIntervalSince1970: 2),
            bundleManifest: try BundleManifest()
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = makeService(store: store, existingFiles: [rootURL])

        #expect(service.getPastRecordings().isEmpty)
        #expect(store.recordings.isEmpty)
    }

    @Test("recoverActiveRecording returns none with no active recording")
    func recoverActiveRecordingWithNoActiveRecording() async {
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(store: store)

        let result = await service.recoverActiveRecording()

        #expect(result == .none)
    }

    @Test("recoverActiveRecording moves playable active recording into history")
    func recoverActiveRecordingWithPlayableFile() async throws {
        let fileURL = URL(fileURLWithPath: "/tmp/playable.mp4")
        let date = Date(timeIntervalSince1970: 100)
        let activeRecording = ActiveRecording(
            fileURL: fileURL,
            name: "Playable",
            date: date,
            options: RecordingOptions(frameRate: 30)
        )
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(store: store, existingFiles: [fileURL], probeResult: .playable)

        let result = await service.recoverActiveRecording()

        let expected = PastRecording(
            fileURL: fileURL,
            name: "Playable",
            date: date,
            options: activeRecording.options
        )
        #expect(result == .playable(expected))
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [expected])
    }

    @Test("recoverActiveRecording probes bundled primary media and stores root")
    func recoverActiveRecordingProbesBundledPrimaryMediaAndStoresRoot() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let cameraURL = rootURL.appendingPathComponent("camera.mov")
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .camera, syncOffsetMilliseconds: 12)
        ])
        let date = Date(timeIntervalSince1970: 100)
        let activeRecording = ActiveRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: date,
            options: RecordingOptions(frameRate: 30),
            bundleManifest: manifest
        )
        let probe = RecordingHistoryMediaProbeSpy(result: .playable)
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(
            store: store,
            existingFiles: [rootURL, rootURL.appendingPathComponent("screen.mov"), cameraURL],
            mediaProbe: probe
        )

        let result = await service.recoverActiveRecording()

        let expected = PastRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: date,
            options: activeRecording.options,
            bundleManifest: manifest
        )
        #expect(probe.inspectedURLs == [rootURL.appendingPathComponent("screen.mov")])
        #expect(result == .playable(expected))
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [expected])
    }

    @Test("recoverActiveRecording drops missing bundle sidecars")
    func recoverActiveRecordingDropsMissingBundleSidecars() async throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let manifest = try BundleManifest(sidecars: [
            BundleSidecarManifest(kind: .captions)
        ])
        let sanitizedManifest = try BundleManifest()
        let date = Date(timeIntervalSince1970: 100)
        let activeRecording = ActiveRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: date,
            options: RecordingOptions(frameRate: 30),
            bundleManifest: manifest
        )
        let diagnosticClient = RecordingHistoryDiagnosticSpy()
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(
            store: store,
            existingFiles: [rootURL, rootURL.appendingPathComponent("screen.mov")],
            now: Date(timeIntervalSince1970: 500),
            probeResult: .playable,
            diagnosticClient: diagnosticClient
        )

        let result = await service.recoverActiveRecording()

        let expected = PastRecording(
            fileURL: rootURL,
            name: "Bundled",
            date: date,
            options: activeRecording.options,
            bundleManifest: sanitizedManifest
        )
        #expect(result == .playable(expected))
        #expect(store.recordings == [expected])
        #expect(
            diagnosticClient.diagnostics == [
                CorruptRecordingDiagnostic(
                    fileURL: rootURL.appendingPathComponent("captions.json"),
                    reason: "Missing bundle sidecar",
                    recordedAt: Date(timeIntervalSince1970: 500)
                )
            ])
    }

    @Test("recoverActiveRecording identifies known corrupt active recording without adding history")
    func recoverActiveRecordingWithKnownCorruptFile() async {
        let fileURL = URL(fileURLWithPath: "/tmp/corrupt.mp4")
        let diagnosticClient = RecordingHistoryDiagnosticSpy()
        let activeRecording = ActiveRecording(
            fileURL: fileURL,
            name: "Corrupt",
            date: Date(timeIntervalSince1970: 100),
            options: RecordingOptions(frameRate: 30)
        )
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(
            store: store,
            existingFiles: [fileURL],
            probeResult: .corrupt(reason: "moov atom not found"),
            diagnosticClient: diagnosticClient
        )

        let result = await service.recoverActiveRecording()

        #expect(result == .knownCorrupt(fileURL: fileURL, reason: "moov atom not found"))
        #expect(diagnosticClient.diagnostics.isEmpty)
        #expect(store.activeRecording == nil)
        #expect(store.recordings.isEmpty)
    }

    @Test("recoverActiveRecording records diagnostics for unknown corrupt active recording")
    func recoverActiveRecordingWithUnknownCorruptFile() async {
        let fileURL = URL(fileURLWithPath: "/tmp/unknown-corrupt.mp4")
        let now = Date(timeIntervalSince1970: 500)
        let diagnosticClient = RecordingHistoryDiagnosticSpy()
        let activeRecording = ActiveRecording(
            fileURL: fileURL,
            name: "Unknown Corrupt",
            date: Date(timeIntervalSince1970: 100),
            options: RecordingOptions(frameRate: 30)
        )
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(
            store: store,
            existingFiles: [fileURL],
            now: now,
            probeResult: .corrupt(reason: "unexpected decoder failure"),
            diagnosticClient: diagnosticClient
        )

        let result = await service.recoverActiveRecording()

        #expect(result == .unknownCorrupt(fileURL: fileURL, reason: "unexpected decoder failure"))
        #expect(
            diagnosticClient.diagnostics == [
                CorruptRecordingDiagnostic(
                    fileURL: fileURL,
                    reason: "unexpected decoder failure",
                    recordedAt: now
                )
            ])
        #expect(store.activeRecording == nil)
        #expect(store.recordings.isEmpty)
    }

}
