import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    func rebuildEditedPreview() {
        previewCompositionTask?.cancel()
        guard let source else {
            return
        }

        let sourceURL = source.fileURL
        let plan = transcriptEditPlan
        let sourceTime = currentPlaybackTime
        let wasPlaying = playbackRequested

        guard !plan.cuts.isEmpty else {
            isEditedPreviewReady = true
            let item = AVPlayerItem(url: sourceURL)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            enqueuePreviewSeek(to: min(max(sourceTime, trimStart), trimEnd), resume: wasPlaying)
            return
        }

        guard let segments = try? previewTimelineMapper.sourceSegments else {
            isEditedPreviewReady = false
            transcriptEditStatusMessage = "Could not build the edited preview."
            return
        }

        isEditedPreviewReady = false
        transcriptEditStatusMessage = "Updating edited preview…"
        previewCompositionTask = Task { [weak self] in
            do {
                let asset = try await AVFoundationEditorPreviewAssetBuilder().makePreviewAsset(
                    inputFileURL: sourceURL,
                    sourceSegments: segments
                )
                try Task.checkCancellation()
                self?.applyEditedPreview(
                    asset,
                    sourceURL: sourceURL,
                    plan: plan,
                    sourceTime: sourceTime,
                    wasPlaying: wasPlaying
                )
            } catch is CancellationError {
            } catch {
                self?.applyEditedPreviewFailure(sourceURL: sourceURL)
            }
        }
    }

    private func applyEditedPreview(
        _ asset: AVComposition,
        sourceURL: URL,
        plan: TimelineEditPlan,
        sourceTime: TimeInterval,
        wasPlaying: Bool
    ) {
        guard source?.fileURL == sourceURL, transcriptEditPlan == plan else {
            return
        }

        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        let outputTime = previewOutputTime(forSourceTime: sourceTime)
        currentPlaybackTime =
            previewTimelineMapper.sourceTime(forOutputTime: outputTime) ?? trimStart
        enqueuePreviewSeek(to: outputTime, resume: wasPlaying)
        isEditedPreviewReady = true
        transcriptEditStatusMessage = "Word cut"
        previewCompositionTask = nil
    }

    private func applyEditedPreviewFailure(sourceURL: URL) {
        guard source?.fileURL == sourceURL else {
            return
        }
        let item = AVPlayerItem(url: sourceURL)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        transcriptEditStatusMessage = "Edited preview unavailable; undo the cut to export."
        isEditedPreviewReady = false
        previewCompositionTask = nil
    }

    func previewOutputTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        if let mapped = previewTimelineMapper.outputTime(forSourceTime: sourceTime) {
            return mapped
        }

        guard let segments = try? previewTimelineMapper.sourceSegments else {
            return 0
        }
        if let next = segments.first(where: { $0.sourceRange.start > sourceTime }) {
            return next.outputStart
        }
        return (try? previewTimelineMapper.unscaledOutputDuration) ?? 0
    }

    private func enqueuePreviewSeek(to outputTime: TimeInterval, resume: Bool) {
        player.seek(
            to: CMTime(seconds: outputTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished, resume else {
                return
            }
            Task { @MainActor in
                guard let self else {
                    return
                }
                self.player.rate = Float(self.playbackSpeed.value)
            }
        }
    }
}
