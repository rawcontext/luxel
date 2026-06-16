import Foundation
import LuxelCore
import Testing

@MainActor
@Suite("Screenshot capture service")
struct ScreenshotCaptureServiceTests {
    @Test("capture fans out to clipboard and file while recording history")
    func captureFansOutToClipboardAndFile() async throws {
        let imageData = try makeImageData()
        let capturer = StubStillCapturer(imageData: imageData)
        let fileSystem = SpyScreenshotFileSystem()
        let destinationClient = SpyScreenshotDestinationClient()
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(
            capturer: capturer,
            fileSystem: fileSystem,
            destinationClient: destinationClient,
            store: store
        )
        let request = try makeScreenshotRequest()
        let outputURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let job = try ScreenshotCaptureJob(
            request: request,
            destinations: [.clipboard, .file],
            outputFileURL: outputURL,
            historyName: "Screenshot"
        )

        let result = try await service.capture(job)

        #expect(capturer.requests == [request])
        #expect(destinationClient.copiedImages == [imageData])
        #expect(fileSystem.writtenFiles == [WrittenImage(imageData: imageData, fileURL: outputURL)])
        #expect(result.completedDestinations == [.clipboard, .file])
        #expect(result.failedDestinations.isEmpty)
        #expect(result.fileURL == outputURL)
        #expect(result.historyEntry == PastRecording(
            fileURL: outputURL,
            name: "Screenshot",
            date: Date(timeIntervalSince1970: 100),
            kind: .screenshot
        ))
        #expect(store.recordings == [try #require(result.historyEntry)])
    }

    @Test("file destination failure does not prevent clipboard destination")
    func fileDestinationFailureDoesNotPreventClipboardDestination() async throws {
        let imageData = try makeImageData()
        let capturer = StubStillCapturer(imageData: imageData)
        let fileSystem = SpyScreenshotFileSystem(writeError: StubError.writeFailed)
        let destinationClient = SpyScreenshotDestinationClient()
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(
            capturer: capturer,
            fileSystem: fileSystem,
            destinationClient: destinationClient,
            store: store
        )
        let outputURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let job = try ScreenshotCaptureJob(
            request: makeScreenshotRequest(),
            destinations: [.file, .clipboard],
            outputFileURL: outputURL
        )

        let result = try await service.capture(job)

        #expect(result.completedDestinations == [.clipboard])
        #expect(result.failedDestinations == [.file])
        #expect(result.fileURL == nil)
        #expect(result.historyEntry == nil)
        #expect(destinationClient.copiedImages == [imageData])
        #expect(store.recordings.isEmpty)
    }

    @Test("file and preview destinations share one written file")
    func fileAndPreviewDestinationsShareOneWrittenFile() async throws {
        let imageData = try makeImageData()
        let capturer = StubStillCapturer(imageData: imageData)
        let fileSystem = SpyScreenshotFileSystem()
        let destinationClient = SpyScreenshotDestinationClient()
        let store = InMemoryRecordingHistoryStore()
        let service = makeService(
            capturer: capturer,
            fileSystem: fileSystem,
            destinationClient: destinationClient,
            store: store
        )
        let outputURL = URL(fileURLWithPath: "/tmp/screenshot.png")
        let job = try ScreenshotCaptureJob(
            request: makeScreenshotRequest(),
            destinations: [.file, .preview],
            outputFileURL: outputURL
        )

        let result = try await service.capture(job)

        #expect(fileSystem.writtenFiles == [WrittenImage(imageData: imageData, fileURL: outputURL)])
        #expect(destinationClient.openedFiles == [outputURL])
        #expect(result.completedDestinations == [.file, .preview])
        #expect(result.failedDestinations.isEmpty)
        #expect(result.historyEntry?.kind == .screenshot)
    }

    @Test("capture failure skips destinations")
    func captureFailureSkipsDestinations() async throws {
        let capturer = StubStillCapturer(error: StubError.captureFailed)
        let fileSystem = SpyScreenshotFileSystem()
        let destinationClient = SpyScreenshotDestinationClient()
        let service = makeService(
            capturer: capturer,
            fileSystem: fileSystem,
            destinationClient: destinationClient
        )
        let job = try ScreenshotCaptureJob(
            request: makeScreenshotRequest(),
            destinations: [.clipboard, .file],
            outputFileURL: URL(fileURLWithPath: "/tmp/screenshot.png")
        )

        await #expect(throws: StubError.captureFailed) {
            try await service.capture(job)
        }

        #expect(destinationClient.copiedImages.isEmpty)
        #expect(fileSystem.writtenFiles.isEmpty)
    }

    @Test("job validates destinations")
    func jobValidatesDestinations() throws {
        let request = try makeScreenshotRequest()

        #expect(throws: ScreenshotModelError.emptyScreenshotDestinations) {
            try ScreenshotCaptureJob(request: request, destinations: [])
        }

        #expect(throws: ScreenshotModelError.fileDestinationRequiresOutputURL) {
            try ScreenshotCaptureJob(request: request, destinations: [.file])
        }
    }

    private func makeService(
        capturer: StubStillCapturer,
        fileSystem: SpyScreenshotFileSystem,
        destinationClient: SpyScreenshotDestinationClient,
        store: InMemoryRecordingHistoryStore = InMemoryRecordingHistoryStore()
    ) -> ScreenshotCaptureService {
        ScreenshotCaptureService(
            capturer: capturer,
            fileWriter: fileSystem,
            destinationClient: destinationClient,
            history: RecordingHistoryService(
                store: store,
                fileSystem: fileSystem,
                dateProvider: FixedDateProvider(now: Date(timeIntervalSince1970: 100)),
                mediaProbe: StaticMediaProbe(result: .playable)
            )
        )
    }

    private func makeScreenshotRequest() throws -> ScreenshotRequest {
        try ScreenshotRequest(
            target: .display(DisplayID(1)),
            includeCursor: true
        )
    }

    private func makeImageData() throws -> ImageData {
        try ImageData(
            data: Data([0x89, 0x50, 0x4E, 0x47]),
            format: .png,
            pixelSize: PixelSize(width: 100, height: 80)
        )
    }
}

private struct WrittenImage: Equatable {
    let imageData: ImageData
    let fileURL: URL
}

private final class StubStillCapturer: StillCapturer, @unchecked Sendable {
    private let result: Result<ImageData, Error>
    private(set) var requests: [ScreenshotRequest] = []

    init(imageData: ImageData) {
        result = .success(imageData)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func capture(_ request: ScreenshotRequest) async throws -> ImageData {
        requests.append(request)
        return try result.get()
    }
}

@MainActor
private final class SpyScreenshotDestinationClient: ScreenshotDestinationClient {
    var copiedImages: [ImageData] = []
    var openedFiles: [URL] = []

    func copyImageToPasteboard(_ imageData: ImageData) throws {
        copiedImages.append(imageData)
    }

    func openWithDefaultApp(_ fileURL: URL) throws {
        openedFiles.append(fileURL)
    }
}

private final class SpyScreenshotFileSystem: ScreenshotFileWriter, FileSystem, @unchecked Sendable {
    private var existingFiles: Set<URL> = []
    private let writeError: Error?
    private(set) var writtenFiles: [WrittenImage] = []

    init(writeError: Error? = nil) {
        self.writeError = writeError
    }

    func write(_ imageData: ImageData, to fileURL: URL) throws {
        if let writeError {
            throw writeError
        }

        writtenFiles.append(WrittenImage(imageData: imageData, fileURL: fileURL))
        existingFiles.insert(fileURL)
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {
        existingFiles.remove(url)
    }

    func trashItem(at url: URL) throws {
        existingFiles.remove(url)
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
    case captureFailed
    case writeFailed
}
