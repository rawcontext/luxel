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
            let item = AVPlayerItem(url: sourceURL)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            enqueuePreviewSeek(to: min(max(sourceTime, trimStart), trimEnd), resume: wasPlaying)
            return
        }

        guard let segments = try? previewTimelineMapper.sourceSegments else {
            transcriptEditStatusMessage = "Could not build the edited preview."
            return
        }

        previewCompositionTask = Task { [weak self] in
            do {
                let asset = try await AVFoundationEditorPreviewAssetBuilder().makePreviewAsset(
                    inputFileURL: sourceURL,
                    sourceSegments: segments
                )
                try Task.checkCancellation()
                guard let self,
                      self.source?.fileURL == sourceURL,
                      self.transcriptEditPlan == plan
                else {
                    return
                }

                let item = AVPlayerItem(asset: asset)
                item.audioTimePitchAlgorithm = .timeDomain
                self.player.replaceCurrentItem(with: item)
                let outputTime = self.previewOutputTime(forSourceTime: sourceTime)
                self.currentPlaybackTime =
                    self.previewTimelineMapper.sourceTime(forOutputTime: outputTime)
                    ?? self.trimStart
                self.enqueuePreviewSeek(to: outputTime, resume: wasPlaying)
                self.previewCompositionTask = nil
            } catch is CancellationError {
                self?.previewCompositionTask = nil
            } catch {
                guard let self, self.source?.fileURL == sourceURL else {
                    return
                }
                let item = AVPlayerItem(url: sourceURL)
                item.audioTimePitchAlgorithm = .timeDomain
                self.player.replaceCurrentItem(with: item)
                self.transcriptEditStatusMessage = "Edited preview unavailable; export is still available."
                self.previewCompositionTask = nil
            }
        }
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
