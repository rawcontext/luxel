import Foundation
import LuxelCore
import Testing

struct ExportServiceCapturedMediaExport {
    let request: ExportRequest
    let outputFileURL: URL
    let preparedAudio: PreparedAudioAsset?
}

actor ExportServiceSpyMediaExporter: MediaExporter {
    private let reportedProgress: [Double]
    private var captured: [ExportServiceCapturedMediaExport] = []

    init(reportedProgress: [Double] = []) {
        self.reportedProgress = reportedProgress
    }

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        try await export(request, to: outputFileURL, progress: nil)
    }

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        captured.append(
            ExportServiceCapturedMediaExport(
                request: request,
                outputFileURL: outputFileURL,
                preparedAudio: input.preparedAudio
            )
        )
        for value in reportedProgress {
            await progress?(value)
        }

        return try ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExport() -> ExportServiceCapturedMediaExport? {
        captured.last
    }

    func capturedExports() -> [ExportServiceCapturedMediaExport] {
        captured
    }
}

actor ExportServiceSpyExportAudioPreparer: ExportAudioPreparing {
    private let preparedAsset: PreparedAudioAsset
    private let temporaryDirectoryURL: URL
    private var callCount = 0

    init(preparedAsset: PreparedAudioAsset, temporaryDirectoryURL: URL) {
        self.preparedAsset = preparedAsset
        self.temporaryDirectoryURL = temporaryDirectoryURL
    }

    func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        callCount += 1
        let requestIndices = Array(requests.indices)
        await progress?(
            ExportAudioPreparationProgress(
                requestIndices: requestIndices,
                progress: 1
            )
        )
        return PreparedExportAudioSet(
            assetsByRequestIndex: Dictionary(
                uniqueKeysWithValues: requestIndices.map { ($0, preparedAsset) }
            ),
            temporaryDirectoryURL: temporaryDirectoryURL
        )
    }

    func prepareCallCount() -> Int {
        callCount
    }
}

struct ExportServiceWritingMediaExporter: MediaExporter {
    let byteCount: Int

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        let data = Data(repeating: 0x5A, count: byteCount)
        try data.write(to: outputFileURL)
        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

actor ExportServiceProgressRecorder {
    private var captured: [ExportProgressSnapshot] = []

    func append(_ snapshot: ExportProgressSnapshot) {
        captured.append(snapshot)
    }

    func snapshots() -> [ExportProgressSnapshot] {
        captured
    }
}

actor ExportServiceBatchProgressRecorder {
    private var captured: [ExportBatchProgressSnapshot] = []

    func append(_ snapshot: ExportBatchProgressSnapshot) {
        captured.append(snapshot)
    }

    func snapshots() -> [ExportBatchProgressSnapshot] {
        captured
    }
}

actor ExportServiceCancellableMediaExporter: MediaExporter {
    private var started = false
    private var startContinuation: CheckedContinuation<Void, Never>?

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        markStarted()

        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }

        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    private func markStarted() {
        started = true
        startContinuation?.resume()
        startContinuation = nil
    }
}

actor ExportServiceBatchCancellableExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []
    private var hangingExportCount = 0
    private var awaitedHangingExportCount = Int.max
    private var hangingExportsContinuation: CheckedContinuation<Void, Never>?

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        captured.append((request, outputFileURL))

        if request.format == .mp4 {
            return try ExportedMedia(
                fileURL: outputFileURL,
                format: request.format,
                pixelSize: request.outputPixelSize,
                shouldMute: request.outputShouldMute
            )
        }

        markHangingExportStarted()

        while true {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func waitUntilHangingExportsStarted(count: Int) async {
        if hangingExportCount >= count {
            return
        }

        awaitedHangingExportCount = count
        await withCheckedContinuation { continuation in
            hangingExportsContinuation = continuation
        }
    }

    func capturedExports() -> [(request: ExportRequest, outputFileURL: URL)] {
        captured
    }

    private func markHangingExportStarted() {
        hangingExportCount += 1
        if hangingExportCount >= awaitedHangingExportCount {
            hangingExportsContinuation?.resume()
            hangingExportsContinuation = nil
        }
    }
}

final class ExportServiceSpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedRemovedURLs: [URL] = []

    var removedURLs: [URL] {
        lock.withLock {
            capturedRemovedURLs
        }
    }

    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {
        lock.withLock {
            capturedRemovedURLs.append(url)
        }
    }

    func trashItem(at url: URL) throws {}
}
