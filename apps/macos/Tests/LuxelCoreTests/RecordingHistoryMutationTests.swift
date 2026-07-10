import Foundation
import LuxelCore
import Testing

extension RecordingHistoryTests {
    @Test("setCurrentRecording stores generated timestamped name")
    func setCurrentRecordingStoresGeneratedName() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/current.mp4")
        let now = try #require(ISO8601DateFormatter().date(from: "2020-07-21T15:27:26Z"))
        let store = InMemoryRecordingHistoryStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -4 * 60 * 60))
        let service = makeService(store: store, now: now, calendar: calendar)

        service.setCurrentRecording(fileURL: fileURL, options: RecordingOptions(frameRate: 30))

        #expect(
            store.activeRecording
                == ActiveRecording(
                    fileURL: fileURL,
                    name: "Luxel 2020-07-21 at 11.27.26",
                    date: now,
                    options: RecordingOptions(frameRate: 30)
                ))
    }

    @Test("materializeRecordingBundle creates directory and manifest file")
    func materializeRecordingBundleCreatesDirectoryAndManifestFile() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/Luxel Recording")
        let fileSystem = RecordingHistoryFakeFileSystem()
        let service = makeService(store: InMemoryRecordingHistoryStore(), fileSystem: fileSystem)

        let bundle = try service.materializeRecordingBundle(
            rootURL: rootURL,
            sidecars: [
                BundleSidecarManifest(kind: .camera, syncOffsetMilliseconds: 24),
                BundleSidecarManifest(kind: .captions)
            ]
        )

        #expect(fileSystem.createdDirectories == [rootURL])
        #expect(fileSystem.writtenData.map(\.url) == [rootURL.appendingPathComponent("bundle.json")])
        #expect(bundle.primaryURL == rootURL.appendingPathComponent("screen.mov"))
        #expect(bundle.sidecarURL(for: .camera) == rootURL.appendingPathComponent("camera.mov"))
        #expect(bundle.sidecarURL(for: .captions) == rootURL.appendingPathComponent("captions.json"))

        let persistedManifest = try JSONDecoder().decode(
            BundleManifest.self, from: try #require(fileSystem.writtenData.first?.data))
        #expect(persistedManifest == bundle.manifest)
    }

    @Test("stopCurrentRecording moves active recording to front and can rename")
    func stopCurrentRecordingMovesActiveRecordingToFront() {
        let fileURL = URL(fileURLWithPath: "/tmp/current.mp4")
        let firstDate = Date(timeIntervalSince1970: 100)
        let stopDate = Date(timeIntervalSince1970: 200)
        let activeRecording = ActiveRecording(
            fileURL: fileURL,
            name: "Original",
            date: firstDate,
            options: RecordingOptions(frameRate: 30)
        )
        let store = InMemoryRecordingHistoryStore(activeRecording: activeRecording)
        let service = makeService(store: store, existingFiles: [fileURL], now: stopDate)

        service.stopCurrentRecording(recordingName: "Renamed")

        #expect(store.activeRecording == nil)
        #expect(
            store.recordings == [
                PastRecording(
                    fileURL: fileURL,
                    name: "Renamed",
                    date: stopDate,
                    options: activeRecording.options
                )
            ])
    }

    @Test("cleanPastRecordings removes existing files and clears history")
    func cleanPastRecordingsRemovesExistingFiles() throws {
        let existingURL = URL(fileURLWithPath: "/tmp/existing.mp4")
        let missingURL = URL(fileURLWithPath: "/tmp/missing.mp4")
        let fileSystem = RecordingHistoryFakeFileSystem(existingFiles: [existingURL])
        let store = InMemoryRecordingHistoryStore(recordings: [
            PastRecording(fileURL: existingURL, name: "Existing", date: Date(timeIntervalSince1970: 1)),
            PastRecording(fileURL: missingURL, name: "Missing", date: Date(timeIntervalSince1970: 2))
        ])
        let service = makeService(store: store, fileSystem: fileSystem)

        try service.cleanPastRecordings()

        #expect(fileSystem.removedFiles == [existingURL])
        #expect(store.recordings.isEmpty)
    }

    @Test("discardRecording trashes existing file and removes history entry")
    func discardRecordingTrashesFileAndRemovesHistoryEntry() throws {
        let keptURL = URL(fileURLWithPath: "/tmp/kept.mp4")
        let discardedURL = URL(fileURLWithPath: "/tmp/discarded.mp4")
        let kept = PastRecording(fileURL: keptURL, name: "Kept", date: Date(timeIntervalSince1970: 1))
        let discarded = PastRecording(
            fileURL: discardedURL, name: "Discarded", date: Date(timeIntervalSince1970: 2))
        let fileSystem = RecordingHistoryFakeFileSystem(existingFiles: [keptURL, discardedURL])
        let store = InMemoryRecordingHistoryStore(recordings: [discarded, kept])
        let service = makeService(store: store, fileSystem: fileSystem)

        let recordings = try service.discardRecording(discarded)

        #expect(fileSystem.trashedFiles == [discardedURL])
        #expect(recordings == [kept])
        #expect(store.recordings == [kept])
    }

    @Test("discardRecording keeps history entry when trash fails")
    func discardRecordingKeepsHistoryWhenTrashFails() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/discarded.mp4")
        let recording = PastRecording(
            fileURL: fileURL, name: "Discarded", date: Date(timeIntervalSince1970: 2))
        let fileSystem = RecordingHistoryFakeFileSystem(
            existingFiles: [fileURL],
            trashError: RecordingHistoryStubError.trashFailed
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = makeService(store: store, fileSystem: fileSystem)

        #expect(throws: RecordingHistoryStubError.trashFailed) {
            try service.discardRecording(recording)
        }

        #expect(fileSystem.trashedFiles == [fileURL])
        #expect(store.recordings == [recording])
    }

    @Test("addRecording stores only existing files")
    func addRecordingStoresOnlyExistingFiles() {
        let fileURL = URL(fileURLWithPath: "/tmp/new.mp4")
        let missingURL = URL(fileURLWithPath: "/tmp/missing.mp4")
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(store: store, existingFiles: [fileURL])

        let missing = PastRecording(
            fileURL: missingURL, name: "Missing", date: Date(timeIntervalSince1970: 1))
        let existing = PastRecording(
            fileURL: fileURL, name: "Existing", date: Date(timeIntervalSince1970: 2))

        #expect(service.addRecording(missing).isEmpty)
        #expect(service.addRecording(existing) == [existing])
        #expect(store.recordings == [existing])
    }

    @Test("addReplayClip stores timestamped recording history entry")
    func addReplayClipStoresTimestampedRecordingHistoryEntry() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/replay.mp4")
        let now = try #require(ISO8601DateFormatter().date(from: "2020-07-21T15:27:26Z"))
        let store = InMemoryRecordingHistoryStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -4 * 60 * 60))
        let service = makeService(
            store: store,
            existingFiles: [fileURL],
            now: now,
            calendar: calendar
        )

        let recording = service.addReplayClip(fileURL: fileURL)

        let expected = PastRecording(
            fileURL: fileURL,
            name: "Luxel Replay 2020-07-21 at 11.27.26",
            date: now,
            kind: .recording
        )
        #expect(recording == expected)
        #expect(store.recordings == [expected])
    }

    @Test("addReplayClip skips missing files")
    func addReplayClipSkipsMissingFiles() {
        let fileURL = URL(fileURLWithPath: "/tmp/missing-replay.mp4")
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(store: store)

        let recording = service.addReplayClip(fileURL: fileURL, name: "Missing")

        #expect(recording == nil)
        #expect(store.recordings.isEmpty)
    }

    @Test("recordExport stores exported file metadata on matching history entry")
    func recordExportStoresMetadata() throws {
        let recordingURL = URL(fileURLWithPath: "/tmp/new.mp4")
        let exportURL = URL(fileURLWithPath: "/tmp/new Quick GIF.gif")
        let now = Date(timeIntervalSince1970: 300)
        let recording = PastRecording(
            fileURL: recordingURL,
            name: "Existing",
            date: Date(timeIntervalSince1970: 2)
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = makeService(
            store: store,
            existingFiles: [recordingURL, exportURL],
            now: now
        )
        let exportedMedia = try ExportedMedia(
            fileURL: exportURL,
            format: .gif,
            pixelSize: PixelSize(width: 640, height: 360),
            shouldMute: true,
            fileSizeBytes: 42_000
        )

        let recordings = service.recordExport(exportedMedia, presetName: "Quick GIF", for: recording)

        let expectedExport = RecordingExport(
            fileURL: exportURL,
            format: .gif,
            fileSizeBytes: 42_000,
            date: now,
            presetName: "Quick GIF"
        )
        #expect(recordings == [recording.addingExport(expectedExport)])
        #expect(store.recordings == recordings)
    }

    @Test("getPastRecordings prunes missing export history entries")
    func getPastRecordingsPrunesMissingExports() {
        let recordingURL = URL(fileURLWithPath: "/tmp/new.mp4")
        let existingExportURL = URL(fileURLWithPath: "/tmp/new Quick GIF.gif")
        let missingExportURL = URL(fileURLWithPath: "/tmp/new Missing.mp4")
        let recording = PastRecording(
            fileURL: recordingURL,
            name: "Existing",
            date: Date(timeIntervalSince1970: 2),
            exports: [
                RecordingExport(
                    fileURL: existingExportURL,
                    format: .gif,
                    date: Date(timeIntervalSince1970: 3),
                    presetName: "Quick GIF"
                ),
                RecordingExport(
                    fileURL: missingExportURL,
                    format: .mp4,
                    date: Date(timeIntervalSince1970: 4),
                    presetName: "Missing MP4"
                )
            ]
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = makeService(store: store, existingFiles: [recordingURL, existingExportURL])

        let recordings = service.getPastRecordings()

        #expect(
            recordings == [
                recording.filteringExports { $0.fileURL == existingExportURL }
            ])
        #expect(store.recordings == recordings)
    }

}
