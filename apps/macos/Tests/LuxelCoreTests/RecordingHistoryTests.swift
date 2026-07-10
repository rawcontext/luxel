import Foundation
import LuxelCore
import Testing

@Suite("Recording history")
struct RecordingHistoryTests {
}

extension RecordingHistoryTests {
    func makeService(
        store: InMemoryRecordingHistoryStore,
        existingFiles: Set<URL> = [],
        now: Date = Date(timeIntervalSince1970: 0),
        probeResult: MediaProbeResult = .playable,
        mediaProbe: (any MediaProbe)? = nil,
        diagnosticClient: any RecordingDiagnosticClient = NoopRecordingDiagnosticClient(),
        calendar: Calendar = .current
    ) -> RecordingHistoryService {
        makeService(
            store: store,
            fileSystem: RecordingHistoryFakeFileSystem(existingFiles: existingFiles),
            now: now,
            probeResult: probeResult,
            mediaProbe: mediaProbe,
            diagnosticClient: diagnosticClient,
            calendar: calendar
        )
    }

    func makeService(
        store: InMemoryRecordingHistoryStore,
        fileSystem: RecordingHistoryFakeFileSystem,
        now: Date = Date(timeIntervalSince1970: 0),
        probeResult: MediaProbeResult = .playable,
        mediaProbe: (any MediaProbe)? = nil,
        diagnosticClient: any RecordingDiagnosticClient = NoopRecordingDiagnosticClient(),
        calendar: Calendar = .current
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: RecordingHistoryFixedDateProvider(now: now),
            mediaProbe: mediaProbe ?? StaticMediaProbe(result: probeResult),
            diagnosticClient: diagnosticClient,
            calendar: calendar
        )
    }
}

struct RecordingHistoryFixedDateProvider: DateProvider {
    let nowValue: Date

    init(now: Date) {
        self.nowValue = now
    }

    func now() -> Date {
        nowValue
    }
}

enum RecordingHistoryStubError: Error, Equatable {
    case trashFailed
}

final class RecordingHistoryFakeFileSystem: FileSystem, @unchecked Sendable {
    private var existingFiles: Set<URL>
    private(set) var createdDirectories: [URL] = []
    private(set) var writtenData: [RecordingHistoryWrittenData] = []
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

    func createDirectory(at url: URL) throws {
        createdDirectories.append(url)
        existingFiles.insert(url)
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {
        writtenData.append(RecordingHistoryWrittenData(data: data, url: url))
        existingFiles.insert(url)
    }

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

struct RecordingHistoryWrittenData: Equatable {
    let data: Data
    let url: URL
}

final class RecordingHistoryDiagnosticSpy: RecordingDiagnosticClient, @unchecked Sendable {
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

final class RecordingHistoryMediaProbeSpy: MediaProbe, @unchecked Sendable {
    private let lock = NSLock()
    private let result: MediaProbeResult
    private var capturedURLs: [URL] = []

    init(result: MediaProbeResult) {
        self.result = result
    }

    var inspectedURLs: [URL] {
        lock.withLock {
            capturedURLs
        }
    }

    func inspectRecording(at url: URL) async -> MediaProbeResult {
        lock.withLock {
            capturedURLs.append(url)
        }
        return result
    }
}
