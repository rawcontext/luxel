import Foundation
import LuxelCore
import Testing

@Suite("Recording history")
struct RecordingHistoryTests {
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

        #expect(recordings == [PastRecording(fileURL: existingURL, name: "Existing", date: Date(timeIntervalSince1970: 1))])
        #expect(store.recordings == recordings)
    }

    @Test("getPastRecordings filters by history entry kind")
    func getPastRecordingsFiltersByKind() {
        let recordingURL = URL(fileURLWithPath: "/tmp/recording.mp4")
        let screenshotURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let recording = PastRecording(
            fileURL: recordingURL,
            name: "Recording",
            date: Date(timeIntervalSince1970: 2),
            kind: .recording
        )
        let screenshot = PastRecording(
            fileURL: screenshotURL,
            name: "Screenshot",
            date: Date(timeIntervalSince1970: 1),
            kind: .screenshot
        )
        let store = InMemoryRecordingHistoryStore(recordings: [recording, screenshot])
        let service = makeService(store: store, existingFiles: [recordingURL, screenshotURL])

        #expect(service.getPastRecordings(matching: .recordings) == [recording])
        #expect(service.getPastRecordings(matching: .screenshots) == [screenshot])
        #expect(service.getPastRecordings(matching: .all) == [recording, screenshot])
        #expect(store.recordings == [recording, screenshot])
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

    @Test("recoverActiveRecording identifies known corrupt active recording without adding history")
    func recoverActiveRecordingWithKnownCorruptFile() async {
        let fileURL = URL(fileURLWithPath: "/tmp/corrupt.mp4")
        let diagnosticClient = SpyRecordingDiagnosticClient()
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
        let diagnosticClient = SpyRecordingDiagnosticClient()
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
        #expect(diagnosticClient.diagnostics == [
            CorruptRecordingDiagnostic(
                fileURL: fileURL,
                reason: "unexpected decoder failure",
                recordedAt: now
            )
        ])
        #expect(store.activeRecording == nil)
        #expect(store.recordings.isEmpty)
    }

    @Test("setCurrentRecording stores generated timestamped name")
    func setCurrentRecordingStoresGeneratedName() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/current.mp4")
        let now = try #require(ISO8601DateFormatter().date(from: "2020-07-21T15:27:26Z"))
        let store = InMemoryRecordingHistoryStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: -4 * 60 * 60))
        let service = makeService(store: store, now: now, calendar: calendar)

        service.setCurrentRecording(fileURL: fileURL, options: RecordingOptions(frameRate: 30))

        #expect(store.activeRecording == ActiveRecording(
            fileURL: fileURL,
            name: "Luxel 2020-07-21 at 11.27.26",
            date: now,
            options: RecordingOptions(frameRate: 30)
        ))
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
        #expect(store.recordings == [
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
        let fileSystem = FakeFileSystem(existingFiles: [existingURL])
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
        let discarded = PastRecording(fileURL: discardedURL, name: "Discarded", date: Date(timeIntervalSince1970: 2))
        let fileSystem = FakeFileSystem(existingFiles: [keptURL, discardedURL])
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
        let recording = PastRecording(fileURL: fileURL, name: "Discarded", date: Date(timeIntervalSince1970: 2))
        let fileSystem = FakeFileSystem(existingFiles: [fileURL], trashError: StubError.trashFailed)
        let store = InMemoryRecordingHistoryStore(recordings: [recording])
        let service = makeService(store: store, fileSystem: fileSystem)

        #expect(throws: StubError.trashFailed) {
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

        let missing = PastRecording(fileURL: missingURL, name: "Missing", date: Date(timeIntervalSince1970: 1))
        let existing = PastRecording(fileURL: fileURL, name: "Existing", date: Date(timeIntervalSince1970: 2))

        #expect(service.addRecording(missing).isEmpty)
        #expect(service.addRecording(existing) == [existing])
        #expect(store.recordings == [existing])
    }

    @Test("addScreenshot stores screenshot history entry")
    func addScreenshotStoresScreenshotHistoryEntry() throws {
        let fileURL = URL(fileURLWithPath: "/tmp/screenshot.png")
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

        let screenshot = service.addScreenshot(fileURL: fileURL)

        let expected = PastRecording(
            fileURL: fileURL,
            name: "Luxel 2020-07-21 at 11.27.26",
            date: now,
            kind: .screenshot
        )
        #expect(screenshot == expected)
        #expect(store.recordings == [expected])
    }

    @Test("addScreenshot skips missing files")
    func addScreenshotSkipsMissingFiles() {
        let fileURL = URL(fileURLWithPath: "/tmp/missing-screenshot.png")
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(store: store)

        let screenshot = service.addScreenshot(fileURL: fileURL, name: "Missing")

        #expect(screenshot == nil)
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

        #expect(recordings == [
            recording.filteringExports { $0.fileURL == existingExportURL }
        ])
        #expect(store.recordings == recordings)
    }

    private func makeService(
        store: InMemoryRecordingHistoryStore,
        existingFiles: Set<URL> = [],
        now: Date = Date(timeIntervalSince1970: 0),
        probeResult: MediaProbeResult = .playable,
        diagnosticClient: any RecordingDiagnosticClient = NoopRecordingDiagnosticClient(),
        calendar: Calendar = .current
    ) -> RecordingHistoryService {
        makeService(
            store: store,
            fileSystem: FakeFileSystem(existingFiles: existingFiles),
            now: now,
            probeResult: probeResult,
            diagnosticClient: diagnosticClient,
            calendar: calendar
        )
    }

    private func makeService(
        store: InMemoryRecordingHistoryStore,
        fileSystem: FakeFileSystem,
        now: Date = Date(timeIntervalSince1970: 0),
        probeResult: MediaProbeResult = .playable,
        diagnosticClient: any RecordingDiagnosticClient = NoopRecordingDiagnosticClient(),
        calendar: Calendar = .current
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: FixedDateProvider(now: now),
            mediaProbe: StaticMediaProbe(result: probeResult),
            diagnosticClient: diagnosticClient,
            calendar: calendar
        )
    }
}

private struct FixedDateProvider: DateProvider {
    let nowValue: Date

    init(now: Date) {
        self.nowValue = now
    }

    func now() -> Date {
        nowValue
    }
}

private enum StubError: Error, Equatable {
    case trashFailed
}

private final class FakeFileSystem: FileSystem, @unchecked Sendable {
    private var existingFiles: Set<URL>
    private(set) var removedFiles: [URL] = []
    private(set) var trashedFiles: [URL] = []
    private let trashError: Error?

    init(existingFiles: Set<URL> = [], trashError: Error? = nil) {
        self.existingFiles = existingFiles
        self.trashError = trashError
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func removeFile(at url: URL) {
        removedFiles.append(url)
        existingFiles.remove(url)
    }

    func trashItem(at url: URL) throws {
        trashedFiles.append(url)

        if let trashError {
            throw trashError
        }

        existingFiles.remove(url)
    }
}

private final class SpyRecordingDiagnosticClient: RecordingDiagnosticClient, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedDiagnostics: [CorruptRecordingDiagnostic] = []

    var diagnostics: [CorruptRecordingDiagnostic] {
        lock.withLock {
            capturedDiagnostics
        }
    }

    func recordCorruptRecording(_ diagnostic: CorruptRecordingDiagnostic) {
        lock.withLock {
            capturedDiagnostics.append(diagnostic)
        }
    }
}
