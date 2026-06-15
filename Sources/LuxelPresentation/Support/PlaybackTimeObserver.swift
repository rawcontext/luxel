import AVKit
import Foundation

final class PlaybackTimeObserver {
    private let player: AVPlayer
    private let token: Any

    init(player: AVPlayer, onTick: @escaping @MainActor @Sendable (TimeInterval) -> Void) {
        self.player = player
        token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else {
                return
            }

            Task { @MainActor in
                onTick(seconds)
            }
        }
    }

    deinit {
        player.removeTimeObserver(token)
    }
}
