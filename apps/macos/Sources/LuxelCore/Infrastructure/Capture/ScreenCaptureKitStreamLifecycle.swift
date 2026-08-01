import Foundation
import ScreenCaptureKit

enum ScreenCaptureKitStreamLifecycle {
    static func start(
        _ stream: SCStream,
        timeout: Duration,
        timeoutError: @escaping @Sendable () -> any Error
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completion = Completion(continuation)
            let streamHandle = StreamHandle(stream)
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
                    if completion.resume(with: .failure(timeoutError())) {
                        streamHandle.stopCaptureIgnoringResult()
                    }
                } catch {
                    return
                }
            }
        }
    }

    static func stop(_ stream: SCStream, timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completion = Completion(continuation)
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
                } catch {
                    return
                }
            }
        }
    }
}

private struct StreamHandle: @unchecked Sendable {
    private let stream: SCStream

    init(_ stream: SCStream) {
        self.stream = stream
    }

    func stopCaptureIgnoringResult() {
        stream.stopCapture { _ in }
    }
}

private final class Completion: @unchecked Sendable {
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
