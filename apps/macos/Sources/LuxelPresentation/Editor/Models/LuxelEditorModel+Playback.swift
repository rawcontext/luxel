import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    func installPlaybackLoopObserver() {
        guard playbackTimeObserver == nil else {
            return
        }

        playbackTimeObserver = PlaybackTimeObserver(player: player) { [weak self] seconds in
            self?.handlePlaybackTime(seconds)
        }
    }

    func handlePlaybackTime(_ currentTime: TimeInterval) {
        currentPlaybackTime = currentTime

        guard playbackRequested else {
            return
        }

        seekPlaybackIntoTrimRangeIfNeeded(currentTime: currentTime)
    }

    func seekPlaybackIntoTrimRangeIfNeeded(currentTime: TimeInterval? = nil) {
        guard let loop = playbackLoop else {
            return
        }

        let seconds = currentTime ?? CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, let target = loop.seekTarget(for: seconds) else {
            return
        }

        enqueuePlayerSeek(to: target)
    }

    // Frame-accurate seeks are expensive; issuing one per slider tick floods the
    // player pipeline and stalls the UI. Keep at most one seek in flight and
    // remember only the latest requested target.
    private func enqueuePlayerSeek(to target: TimeInterval) {
        pendingPlayerSeekTarget = target
        performPendingPlayerSeekIfIdle()
    }

    private func performPendingPlayerSeekIfIdle() {
        guard !isPlayerSeekInProgress, let target = pendingPlayerSeekTarget else {
            return
        }

        pendingPlayerSeekTarget = nil
        isPlayerSeekInProgress = true
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isPlayerSeekInProgress = false
                self.performPendingPlayerSeekIfIdle()
            }
        }
    }

    var playbackLoop: EditorPlaybackLoop? {
        guard let trimRange = try? TimeRange(start: trimStart, end: trimEnd) else {
            return nil
        }

        return EditorPlaybackLoop(trimRange: trimRange)
    }
}
