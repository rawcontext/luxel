import Foundation
import ScreenCaptureKit

public final class ScreenCaptureKitRecorder: NSObject, CaptureRecorder, @unchecked Sendable {
    private let contentFilterProvider: any ScreenCaptureKitContentFilterProvider
    private let configurationFactory: ScreenRecordingConfigurationFactory
    private let segmentComposer: AVFoundationRecordingSegmentComposer
    private let fileManager: FileManager
    private let contentFilterTimeout: Duration = .seconds(10)
    private let streamStartTimeout: Duration = .seconds(10)
    private let recordingOutputFinishTimeout: Duration = .seconds(2)
    private let streamStopTimeout: Duration = .seconds(5)
    private var stream: SCStream?
    private var isStreamCapturing = false
    private var request: RecordingRequest?
    private var recordingOutput: SCRecordingOutput?
    private var currentSegmentFileURL: URL?
    private var segmentFileURLs: [URL] = []
    private var delegate: RecorderDelegate?

    public init(
        contentFilterProvider: any ScreenCaptureKitContentFilterProvider = ShareableContentFilterProvider(),
        configurationFactory: ScreenRecordingConfigurationFactory = ScreenRecordingConfigurationFactory(),
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

        let contentFilter = try await prepareContentFilter(for: request.target)
        let delegate = RecorderDelegate()
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
            try await startStreamCapture(stream)
            isStreamCapturing = true
        } catch let error as ScreenCaptureKitRecorderError {
            clearRecordingState(removeTemporarySegments: true, preserving: request.outputFileURL)
            throw error
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

}

private extension ScreenCaptureKitRecorder {
    private func prepareContentFilter(for target: CaptureTarget) async throws -> SCContentFilter {
        let completion = ScreenCaptureKitContentFilterCompletion()
        let providerTask = Task { [contentFilterProvider] in
            do {
                let filter = try await contentFilterProvider.contentFilter(for: target)
                _ = completion.resume(with: .success(PreparedContentFilter(filter: filter)))
            } catch {
                _ = completion.resume(with: .failure(error))
            }
        }
        let timeoutTask = Task { [contentFilterTimeout] in
            do {
                try await Task.sleep(for: contentFilterTimeout)
                let timeoutError = ScreenCaptureKitRecorderError.startFailed("Timed out preparing capture")
                if completion.resume(with: .failure(timeoutError)) {
                    providerTask.cancel()
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        defer {
            providerTask.cancel()
            timeoutTask.cancel()
        }

        return try await completion.value().filter
    }

    private struct PreparedContentFilter: @unchecked Sendable {
        let filter: SCContentFilter
    }

    private func makeRecordingOutput(
        for request: RecordingRequest,
        outputFileURL: URL,
        delegate: RecorderDelegate
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

    private func startStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStartTimeout

        try await withCheckedThrowingContinuation { continuation in
            let streamHandle = ScreenCaptureKitStreamHandle(stream)
            let completion = ScreenCaptureKitRecorderCompletion(continuation)
            stream.startCapture { error in
                if let error {
                    _ = completion.resume(with: .failure(error))
                } else if !completion.resume(with: .success(())) {
                    streamHandle.stopCaptureIgnoringResult()
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                    let timeoutError = ScreenCaptureKitRecorderError.startFailed("Timed out starting capture")
                    if completion.resume(with: .failure(timeoutError)) {
                        streamHandle.stopCaptureIgnoringResult()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private func stopStreamCapture(_ stream: SCStream) async throws {
        let timeout = streamStopTimeout

        try await withCheckedThrowingContinuation { continuation in
            let completion = ScreenCaptureKitRecorderCompletion(continuation)
            stream.stopCapture { error in
                if let error {
                    _ = completion.resume(with: .failure(error))
                } else {
                    _ = completion.resume(with: .success(()))
                }
            }

            Task {
                do {
                    try await Task.sleep(for: timeout)
                    _ = completion.resume(with: .success(()))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private struct ScreenCaptureKitStreamHandle: @unchecked Sendable {
        private let stream: SCStream

        init(_ stream: SCStream) {
            self.stream = stream
        }

        func stopCaptureIgnoringResult() {
            stream.stopCapture { _ in }
        }
    }

    private final class ScreenCaptureKitRecorderCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = continuation
        }

        func resume(with result: Result<Void, any Error>) -> Bool {
            let continuation = lock.withLock {
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }

            guard let continuation else {
                return false
            }

            continuation.resume(with: result)
            return true
        }
    }

    private final class ScreenCaptureKitContentFilterCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PreparedContentFilter, any Error>?
        private var result: Result<PreparedContentFilter, any Error>?

        func value() async throws -> PreparedContentFilter {
            try await withCheckedThrowingContinuation { continuation in
                let result: Result<PreparedContentFilter, any Error>? = lock.withLock {
                    if let result = self.result {
                        return result
                    }

                    self.continuation = continuation
                    return nil
                }

                if let result {
                    continuation.resume(with: result)
                }
            }
        }

        func resume(with result: Result<PreparedContentFilter, any Error>) -> Bool {
            let continuation: CheckedContinuation<PreparedContentFilter, any Error>? = lock.withLock {
                guard self.result == nil else {
                    return nil
                }

                self.result = result
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }

            continuation?.resume(with: result)
            return true
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
