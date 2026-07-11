import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

actor SpyAudioPeakAnalyzer: AudioPeakAnalyzer {
    private var capturedRequests: [AudioPeakAnalysisRequest] = []
    private let peaks: [AudioTrackKind: Double]

    init(peaks: [AudioTrackKind: Double] = [:]) {
        self.peaks = peaks
    }

    func measurePeaks(_ request: AudioPeakAnalysisRequest) async throws -> [AudioTrackKind: Double] {
        capturedRequests.append(request)
        return peaks
    }

    func requests() -> [AudioPeakAnalysisRequest] {
        capturedRequests
    }
}

actor SpyAudioTranscriptService: AudioTranscriptService {
    private let transcriptResult: TurnSegmentedTranscript?
    private let transcriptError: (any Error)?
    private let delay: Duration?
    private let progressFractions: [Double]
    private var capturedRequests: [AudioTranscriptRequest] = []

    init(
        transcript: TurnSegmentedTranscript? = nil,
        error: (any Error)? = nil,
        delay: Duration? = nil,
        progressFractions: [Double] = []
    ) {
        self.transcriptResult = transcript
        self.transcriptError = error
        self.delay = delay
        self.progressFractions = progressFractions
    }

    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript? {
        try await performTranscript(for: request)
    }

    func transcript(
        for request: AudioTranscriptRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> TurnSegmentedTranscript? {
        for fraction in progressFractions {
            progress(SpeechTranscriptionProgress(fractionCompleted: fraction))
        }

        let transcript = try await performTranscript(for: request)
        progress(SpeechTranscriptionProgress(fractionCompleted: 1))
        return transcript
    }

    private func performTranscript(
        for request: AudioTranscriptRequest
    ) async throws -> TurnSegmentedTranscript? {
        capturedRequests.append(request)
        if let delay {
            try await Task.sleep(for: delay)
        }
        if let transcriptError {
            throw transcriptError
        }

        return transcriptResult
    }

    func requests() -> [AudioTranscriptRequest] {
        capturedRequests
    }
}

actor StubSpeechAuthorizationService: SpeechRecognitionAuthorizationService {
    private var state: SpeechRecognitionAuthorizationState
    private let requestedState: SpeechRecognitionAuthorizationState
    private var requestCount = 0

    init(
        state: SpeechRecognitionAuthorizationState,
        requestedState: SpeechRecognitionAuthorizationState? = nil
    ) {
        self.state = state
        self.requestedState = requestedState ?? state
    }

    func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState {
        state
    }

    func requestAuthorization() async -> SpeechRecognitionAuthorizationState {
        requestCount += 1
        state = requestedState
        return state
    }

    func requests() -> Int {
        requestCount
    }
}

actor SpyExportSizeEstimator: ExportSizeEstimator {
    private var capturedRequests: [ExportRequest] = []

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        capturedRequests.append(request)
        return try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }

    func request() -> ExportRequest? {
        capturedRequests.last
    }

    func request(for format: ExportFormat) -> ExportRequest? {
        capturedRequests.last { $0.format == format }
    }

    func requests() -> [ExportRequest] {
        capturedRequests
    }
}

struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

final class SpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCreatedDirectories: [URL] = []
    private var capturedCopiedFiles: [CopiedFile] = []
    private var capturedTrashedFiles: [URL] = []
    private let trashError: Error?

    init(trashError: Error? = nil) {
        self.trashError = trashError
    }

    var createdDirectories: [URL] {
        lock.withLock {
            capturedCreatedDirectories
        }
    }

    var copiedFiles: [CopiedFile] {
        lock.withLock {
            capturedCopiedFiles
        }
    }

    var trashedFiles: [URL] {
        lock.withLock {
            capturedTrashedFiles
        }
    }

    func fileExists(at url: URL) -> Bool {
        false
    }

    func createDirectory(at url: URL) throws {
        lock.withLock {
            capturedCreatedDirectories.append(url)
        }
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        lock.withLock {
            capturedCopiedFiles.append(CopiedFile(sourceURL: sourceURL, destinationURL: destinationURL))
        }
    }

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {
        lock.withLock {
            capturedTrashedFiles.append(url)
        }

        if let trashError {
            throw trashError
        }
    }
}

struct CopiedFile: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

@MainActor
final class StubExportedFileActionClient: ExportedFileActionClient {
    let saveDestination: URL?
    private(set) var requestedSaveNames: [String] = []
    private(set) var openedURLs: [URL] = []

    init(saveDestination: URL? = nil) {
        self.saveDestination = saveDestination
    }

    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        requestedSaveNames.append(suggestedFileName)
        return saveDestination
    }

    func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        nil
    }

    func chooseApplicationForOpening(fileURL: URL) -> URL? {
        nil
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func copyFileToPasteboard(_ fileURL: URL) {}

    func copyPathToPasteboard(_ fileURL: URL) {}

    func copyTextToPasteboard(_ text: String) {}

    func revealInFinder(_ fileURL: URL) {}

    func openWithDefaultApp(_ fileURL: URL) {
        openedURLs.append(fileURL)
    }

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {}
}
