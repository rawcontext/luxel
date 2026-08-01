import Foundation
import ScreenCaptureKit

struct PreparedContentFilter: @unchecked Sendable {
    let filter: SCContentFilter
}

final class ScreenCaptureKitContentFilterCompletion: @unchecked Sendable {
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
