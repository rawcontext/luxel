import AVFoundation
import Foundation

public struct AVFoundationAudioInputDeviceUpdateSource: AudioInputDeviceUpdateSource {
    public init() {}

    public func inputDeviceUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let observer = AudioInputDeviceNotificationObserver(continuation: continuation)
            continuation.onTermination = { @Sendable _ in
                observer.stop()
            }
        }
    }
}

private final class AudioInputDeviceNotificationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private let notificationCenter: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(
        continuation: AsyncStream<Void>.Continuation,
        notificationCenter: NotificationCenter = .default
    ) {
        self.notificationCenter = notificationCenter
        tokens = [
            notificationCenter.addObserver(
                forName: AVCaptureDevice.wasConnectedNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            },
            notificationCenter.addObserver(
                forName: AVCaptureDevice.wasDisconnectedNotification,
                object: nil,
                queue: nil
            ) { _ in
                continuation.yield(())
            }
        ]
    }

    func stop() {
        let removedTokens = lock.withLock {
            let currentTokens = tokens
            tokens = []
            return currentTokens
        }

        for token in removedTokens {
            notificationCenter.removeObserver(token)
        }
    }

    deinit {
        stop()
    }
}
