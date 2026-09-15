import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    public func configureAutomaticTitles(onTranscriptionStarted: @escaping @MainActor (URL) -> Void) {
        onTranscriptExtractionStarted = onTranscriptionStarted
    }

    public func refreshAutomaticTitleState(for fileURL: URL) {
        guard let source,
            RecordingDocumentStore.currentMediaURL(for: source.fileURL).standardizedFileURL.resolvingSymlinksInPath()
                == RecordingDocumentStore.currentMediaURL(for: fileURL).standardizedFileURL.resolvingSymlinksInPath()
        else { return }
        isAutomaticTitlePending = RecordingDocumentStore.isTitlePending(for: fileURL)
    }

    public func applyAutomaticRecordingRename(from oldURL: URL, to newURL: URL) {
        guard oldURL != newURL, let source,
            source.fileURL.standardizedFileURL.resolvingSymlinksInPath()
                == oldURL.standardizedFileURL.resolvingSymlinksInPath()
                || RecordingDocumentStore.currentMediaURL(for: source.fileURL).standardizedFileURL
                    .resolvingSymlinksInPath() == newURL.standardizedFileURL.resolvingSymlinksInPath(),
            let renamed = try? source.replacingFileURL(newURL)
        else { return }
        let time = currentFrameTime
        let wasPlaying = playbackRequested
        self.source = renamed
        outputDirectory = RecordingDocumentStore.currentMediaURL(for: outputDirectory)
        recordingNavigationURLs = recordingNavigationURLs.map { RecordingDocumentStore.currentMediaURL(for: $0) }
        let item = AVPlayerItem(url: newURL)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        schedulePreviewAudioMixUpdate()
        if wasPlaying { startPlayback() }
        if !transcriptEditPlan.cuts.isEmpty { rebuildEditedPreview() }
    }
}
