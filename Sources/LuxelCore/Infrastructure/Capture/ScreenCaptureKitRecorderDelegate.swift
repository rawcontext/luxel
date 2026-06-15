import Foundation
import ScreenCaptureKit

final class RecorderDelegate: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
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
