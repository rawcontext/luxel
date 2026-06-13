import Foundation
import ScreenCaptureKit

public final class ScreenCaptureKitRecorder: NSObject, CaptureRecorder, @unchecked Sendable {
    private let contentFilterProvider: any ScreenCaptureKitContentFilterProvider
    private let configurationFactory: ScreenCaptureKitRecordingConfigurationFactory
    private let segmentComposer: AVFoundationRecordingSegmentComposer
    private let fileManager: FileManager
    private let recordingOutputFinishTimeout: Duration = .seconds(2)
    private let streamStopTimeout: Duration = .seconds(5)
    private var stream: SCStream?
    private var isStreamCapturing = false
    private var request: RecordingRequest?
    private var recordingOutput: SCRecordingOutput?
    private var currentSegmentFileURL: URL?
    private var segmentFileURLs: [URL] = []
    private var delegate: ScreenCaptureKitRecorderDelegate?

    public init(
        contentFilterProvider: any ScreenCaptureKitContentFilterProvider = ShareableContentFilterProvider(),
        configurationFactory: ScreenCaptureKitRecordingConfigurationFactory = ScreenCaptureKitRecordingConfigurationFactory(),
        segmentComposer: AVFoundationRecordingSegmentComposer = AVFoundationRecordingSegmentComposer(),
        fileManager: FileManager = .default
    ) {
        self.contentFilterProvider = contentFilterProvider
        self.configurationFactory = configurationFactory
        self.segmentComposer = segmentComposer
        self.fileManager = fileManager
        super.init()
    }

    public func startRecording(_ request: RecordingRequest) async throws {
        guard stream == nil else {
            throw ScreenCaptureKitRecorderError.alreadyRecording
        }

        let contentFilter = try await contentFilterProvider.contentFilter(for: request.target)
        let delegate = ScreenCaptureKitRecorderDelegate()
        let stream = SCStream(
            filter: contentFilter,
            configuration: configurationFactory.makeStreamConfiguration(for: request),
            delegate: delegate
        )
        let recordingOutput = makeRecordingOutput(
            for: request,
            outputFileURL: request.outputFileURL,
            delegate: delegate
        )

        self.stream = stream
        self.request = request
        self.recordingOutput = recordingOutput
        self.currentSegmentFileURL = request.outputFileURL
        self.segmentFileURLs = []
        self.delegate = delegate

        do {
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
            isStreamCapturing = true
        } catch {
            clearRecordingState(removeTemporarySegments: true, preserving: request.outputFileURL)
            throw ScreenCaptureKitRecorderError.startFailed(String(describing: error))
        }
    }

    public func pauseRecording() async throws {
        guard stream != nil else {
            throw ScreenCaptureKitRecorderError.notRecording
        }

        guard recordingOutput != nil else {
            throw ScreenCaptureKitRecorderError.alreadyPaused
        }

        do {
            if let segmentFileURL = try await finishCurrentSegment() {
                segmentFileURLs.append(segmentFileURL)
            }
        } catch {
            throw ScreenCaptureKitRecorderError.pauseFailed(String(describing: error))
        }
    }

    public func resumeRecording() async throws {
        guard let stream, let request, let delegate else {
            throw ScreenCaptureKitRecorderError.notRecording
        }

        guard recordingOutput == nil else {
            throw ScreenCaptureKitRecorderError.notPaused
        }

        do {
            let segmentFileURL = try nextSegmentFileURL()
            let recordingOutput = makeRecordingOutput(
                for: request,
                outputFileURL: segmentFileURL,
                delegate: delegate
            )

            self.recordingOutput = recordingOutput
            self.currentSegmentFileURL = segmentFileURL
            try stream.addRecordingOutput(recordingOutput)
        } catch {
            recordingOutput = nil
            currentSegmentFileURL = nil
            throw ScreenCaptureKitRecorderError.resumeFailed(String(describing: error))
        }
    }

    public func stopRecording() async throws {
        guard let stream else {
            throw ScreenCaptureKitRecorderError.notRecording
        }

        do {
            if isStreamCapturing {
                try await stopStreamCapture(stream)
                isStreamCapturing = false
            }

            if let segmentFileURL = try await finishStoppedCurrentSegment() {
                segmentFileURLs.append(segmentFileURL)
            }

            if let outputFileURL = request?.outputFileURL {
                try await finalizeSegments(to: outputFileURL)
                clearRecordingState(removeTemporarySegments: true, preserving: outputFileURL)
            } else {
                clearRecordingState(removeTemporarySegments: true)
            }
        } catch {
            throw ScreenCaptureKitRecorderError.stopFailed(String(describing: error))
        }
    }

    private func makeRecordingOutput(
        for request: RecordingRequest,
        outputFileURL: URL,
        delegate: ScreenCaptureKitRecorderDelegate
    ) -> SCRecordingOutput {
        SCRecordingOutput(
            configuration: configurationFactory.makeRecordingOutputConfiguration(
                for: request,
                outputFileURL: outputFileURL
            ),
            delegate: delegate
        )
    }

    private func finishCurrentSegment() async throws -> URL? {
        guard let stream, let recordingOutput, let delegate else {
            return nil
        }

        let segmentFileURL = currentSegmentFileURL
        try stream.removeRecordingOutput(recordingOutput)
        try await delegate.waitUntilFinished(recordingOutput, timeout: recordingOutputFinishTimeout)
        self.recordingOutput = nil
        currentSegmentFileURL = nil
        return segmentFileURL
    }

    private func finishStoppedCurrentSegment() async throws -> URL? {
        guard let recordingOutput, let delegate else {
            return nil
        }

        let segmentFileURL = currentSegmentFileURL
        try await delegate.waitUntilFinished(recordingOutput, timeout: recordingOutputFinishTimeout)
        self.recordingOutput = nil
        currentSegmentFileURL = nil
        return segmentFileURL
    }

    private func stopStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStopTimeout

        try await withCheckedThrowingContinuation { continuation in
            let completion = ScreenCaptureKitRecorderStopCompletion(continuation)
            stream.stopCapture { error in
                if let error {
                    completion.resume(with: .failure(error))
                } else {
                    completion.resume(with: .success(()))
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                    completion.resume(with: .success(()))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private final class ScreenCaptureKitRecorderStopCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<Void, any Error>) {
            let continuation = lock.withLock {
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }

            continuation?.resume(with: result)
        }
    }

    private func finalizeSegments(to outputFileURL: URL) async throws {
        guard !segmentFileURLs.isEmpty else {
            return
        }

        if segmentFileURLs.count == 1, segmentFileURLs[0] == outputFileURL {
            return
        }

        try await segmentComposer.compose(segmentFileURLs, to: outputFileURL)
    }

    private func nextSegmentFileURL() throws -> URL {
        let segmentsDirectory = fileManager.temporaryDirectory
            .appending(path: "LuxelRecordingSegments", directoryHint: .isDirectory)

        try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)

        return segmentsDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension("mp4")
    }

    private func clearRecordingState(
        removeTemporarySegments: Bool = false,
        preserving preservedFileURL: URL? = nil
    ) {
        let cleanupFileURLs = segmentFileURLs + [currentSegmentFileURL].compactMap(\.self)

        if removeTemporarySegments {
            for fileURL in cleanupFileURLs where fileURL != preservedFileURL {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        stream = nil
        isStreamCapturing = false
        request = nil
        recordingOutput = nil
        currentSegmentFileURL = nil
        segmentFileURLs = []
        delegate = nil
    }
}

public enum ScreenCaptureKitRecorderError: Error, Equatable {
    case alreadyRecording
    case alreadyPaused
    case notRecording
    case notPaused
    case startFailed(String)
    case pauseFailed(String)
    case resumeFailed(String)
    case stopFailed(String)
}

private final class ScreenCaptureKitRecorderDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var finishedResults: [ObjectIdentifier: Result<Void, any Error>] = [:]
    private var finishContinuations: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]
    private var timedOutOutputIDs: Set<ObjectIdentifier> = []

    func waitUntilFinished(_ recordingOutput: SCRecordingOutput, timeout: Duration) async throws {
        let outputID = ObjectIdentifier(recordingOutput)
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: timeout)
                self?.finishTimedOut(outputID)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        defer {
            timeoutTask.cancel()
        }

        try await withCheckedThrowingContinuation { continuation in
            let finishedResult: Result<Void, any Error>? = lock.withLock {
                if let result = finishedResults.removeValue(forKey: outputID) {
                    return result
                }

                finishContinuations[outputID] = continuation
                return nil
            }

            if let finishedResult {
                continuation.resume(with: finishedResult)
            }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finish(recordingOutput, with: .success(()))
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        finish(recordingOutput, with: .failure(error))
    }

    private func finish(_ recordingOutput: SCRecordingOutput, with result: Result<Void, any Error>) {
        let outputID = ObjectIdentifier(recordingOutput)
        finish(outputID, with: result)
    }

    private func finish(_ outputID: ObjectIdentifier, with result: Result<Void, any Error>) {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            if timedOutOutputIDs.remove(outputID) != nil {
                return nil
            }

            if let continuation = finishContinuations.removeValue(forKey: outputID) {
                return continuation
            }

            finishedResults[outputID] = result
            return nil
        }

        continuation?.resume(with: result)
    }

    private func finishTimedOut(_ outputID: ObjectIdentifier) {
        let continuation: CheckedContinuation<Void, any Error>? = lock.withLock {
            timedOutOutputIDs.insert(outputID)
            return finishContinuations.removeValue(forKey: outputID)
        }

        continuation?.resume(returning: ())
    }
}
