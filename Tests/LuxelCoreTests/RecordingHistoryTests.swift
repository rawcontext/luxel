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

        let expected = PastRecording(fileURL: fileURL, name: "Playable", date: date)
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
            PastRecording(fileURL: fileURL, name: "Renamed", date: stopDate)
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

private final class FakeFileSystem: FileSystem, @unchecked Sendable {
    private var existingFiles: Set<URL>
    private(set) var removedFiles: [URL] = []

    init(existingFiles: Set<URL> = []) {
        self.existingFiles = existingFiles
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func removeFile(at url: URL) {
        removedFiles.append(url)
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
