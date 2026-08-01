@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

final class AudioOnlyWriterFinishCompletion: @unchecked Sendable {
    private let segment: ScreenCaptureKitAudioOnlyWriterSegment
    private let writer: AVAssetWriter
    private let outputFileURL: URL
    private let fileManager: FileManager
    private let continuation: CheckedContinuation<Void, any Error>

    init(
        segment: ScreenCaptureKitAudioOnlyWriterSegment,
        writer: AVAssetWriter,
        outputFileURL: URL,
        fileManager: FileManager,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        self.segment = segment
        self.writer = writer
        self.outputFileURL = outputFileURL
        self.fileManager = fileManager
        self.continuation = continuation
    }

    func resume() {
        withExtendedLifetime(segment) {
            switch writer.status {
            case .completed:
                continuation.resume()
            case .failed, .cancelled:
                try? fileManager.removeItem(at: outputFileURL)
                let message =
                    writer.error.map(String.init(describing:)) ?? String(describing: writer.status)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(message)
                )
            case .unknown, .writing:
                try? fileManager.removeItem(at: outputFileURL)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            @unknown default:
                try? fileManager.removeItem(at: outputFileURL)
                continuation.resume(
                    throwing: ScreenCaptureKitAudioOnlyRecorderError.finishFailed(
                        String(describing: writer.status)
                    ))
            }
        }
    }
}
