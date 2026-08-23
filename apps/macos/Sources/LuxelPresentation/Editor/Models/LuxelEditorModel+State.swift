import AVKit
import Foundation
import LuxelCore

struct TranscriptCutReviewItem: Equatable, Identifiable {
    let id: String
    let text: String
    let sourceRange: TimeRange
}

extension LuxelEditorModel {
    var hasSource: Bool {
        source != nil
    }

    var hasVideoSource: Bool {
        source?.hasVideo == true
    }

    var hasAudioOnlySource: Bool {
        source?.isAudioOnly == true
    }

    var supportedFormats: [ExportFormat] {
        if hasAudioOnlySource {
            return ExportFormat.audioOnlyFormats
        }

        return configuredSupportedFormats
    }

    var duration: TimeInterval {
        source?.duration ?? 1
    }

    var minimumTrimDuration: TimeInterval {
        min(0.1, max(0.001, duration / 100))
    }

    var canIncludeAudio: Bool {
        source?.hasAudio == true && !format.dropsAudio
    }

    var canToggleAudioInclusion: Bool {
        canIncludeAudio && !hasAudioOnlySource
    }

    var maximumFrameRate: Int {
        max(Self.defaultFrameRate, source?.nominalFrameRate.framesPerSecond ?? 120)
    }

    var availableQualities: [ExportQuality] {
        ExportQuality.availableQualities(for: format)
    }

    var canChooseQuality: Bool {
        availableQualities.count > 1
    }

    var showsGIFOptions: Bool {
        format == .gif
    }

    var activeKeystrokeChips: [KeystrokeChip] {
        guard let keystrokeTimeline,
            let keystrokeOptions,
            let chips = try? KeystrokeChipPlanner(renderOptions: keystrokeOptions)
                .plannedChips(for: keystrokeTimeline)
        else {
            return []
        }
        return KeystrokeOverlayLayout.activeChips(at: currentPlaybackTime, in: chips)
    }

    var gifLoopMode: GIFLoopMode {
        switch gifLoopModeKind {
        case .forever:
            .forever
        case .none:
            .none
        case .count:
            .count(gifLoopCount)
        case .bounce:
            .bounce
        }
    }

    var selectedFormatSummary: String {
        if selectedFormats.count == 1 {
            return selectedFormats[0].prettyName
        }

        return "\(selectedFormats.count) Formats"
    }

    var includesAudio: Bool {
        canIncludeAudio && !shouldMute
    }

    var canAdjustAudioMix: Bool {
        includesAudio
    }

    var canUseStudioVoice: Bool {
        includesAudio
    }

    var audioVolumePercentSummary: String {
        "\(Int((audioVolume * 100).rounded()))%"
    }

    var playbackSpeedValue: Double {
        playbackSpeed.value
    }

    var outputDurationSummary: String {
        formatTime((try? editedTimelineMapper.outputDuration) ?? minimumTrimDuration)
    }

    var editedTimelineMapper: EditedTimelineMapper {
        guard let trimRange = try? TimeRange(start: trimStart, end: trimEnd) else {
            preconditionFailure("Editor trim state must remain valid.")
        }
        return EditedTimelineMapper(
            trimRange: trimRange,
            editPlan: transcriptEditPlan,
            speed: playbackSpeed
        )
    }

    var previewTimelineMapper: EditedTimelineMapper {
        EditedTimelineMapper(
            trimRange: editedTimelineMapper.trimRange,
            editPlan: transcriptEditPlan
        )
    }

    var editableTranscriptWords: [TranscriptEditableWord] {
        cachedTranscriptWords
    }

    var visibleTranscriptWords: [TranscriptEditableWord] {
        cachedVisibleTranscriptWords
    }

    var canDeleteSelectedTranscriptWord: Bool {
        !isExporting && !selectedTranscriptWordIDs.isEmpty
            && selectedTranscriptWordIDs.isSubset(of: cachedVisibleTranscriptWordIDs)
    }

    var transcriptCutReviewItems: [TranscriptCutReviewItem] {
        cachedTranscriptCutReviewItems
    }

    var canUndoLastTranscriptCut: Bool {
        guard let lastTranscriptCutID else {
            return false
        }
        return transcriptEditPlan.cuts.contains { $0.id == lastTranscriptCutID }
    }

    var activeTranscriptTurnID: String? {
        guard let transcript = visibleTranscript else {
            return nil
        }
        var lowerBound = transcript.turns.startIndex
        var upperBound = transcript.turns.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if transcript.turns[middle].start <= currentPlaybackTime {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound > transcript.turns.startIndex else {
            return nil
        }
        let turn = transcript.turns[lowerBound - 1]
        return cachedVisibleTranscriptTurnIDs.contains(turn.id)
            && currentPlaybackTime < turn.end
            ? turn.id
            : nil
    }

    var activeTranscriptSpanID: String? {
        guard visibleTranscript != nil else {
            return nil
        }
        var lowerBound = cachedVisibleTranscriptWords.startIndex
        var upperBound = cachedVisibleTranscriptWords.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if cachedVisibleTranscriptWords[middle].sourceRange.start <= currentPlaybackTime {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        guard lowerBound > cachedVisibleTranscriptWords.startIndex else {
            return nil
        }
        let word = cachedVisibleTranscriptWords[lowerBound - 1]
        return currentPlaybackTime < word.sourceRange.end ? word.id : nil
    }

    func rebuildTranscriptWordCache() {
        cachedTranscriptWords =
            transcript.flatMap {
                try? TranscriptWordIndex(transcript: $0).words
            } ?? []
        refreshVisibleTranscriptWordCache()
    }

    func refreshVisibleTranscriptWordCache() {
        cachedVisibleTranscriptWords = cachedTranscriptWords.filter {
            !transcriptEditPlan.removes($0.sourceRange)
        }
        cachedVisibleTranscriptWordIDs = Set(cachedVisibleTranscriptWords.map(\.id))
        cachedVisibleTranscriptWordIndexByID = Dictionary(
            uniqueKeysWithValues: cachedVisibleTranscriptWords.enumerated().map { ($1.id, $0) }
        )
        cachedVisibleTranscriptTurnIDs = Set(cachedVisibleTranscriptWords.map(\.turnID))
        let wordsByID = Dictionary(uniqueKeysWithValues: cachedTranscriptWords.map { ($0.id, $0) })
        cachedTranscriptCutReviewItems = transcriptEditPlan.cuts.map { cut in
            TranscriptCutReviewItem(
                id: cut.id,
                text: cut.transcriptSpanIDs.compactMap { wordsByID[$0]?.text }.joined(separator: " "),
                sourceRange: cut.sourceRange
            )
        }
        transcriptDisplayRevision &+= 1
    }

    var isExporting: Bool {
        status == .exporting || status == .savingOriginal
    }

    var isLoadingSource: Bool {
        if case .loading = status {
            return true
        }

        return false
    }

    var isGrabbingFrame: Bool {
        frameGrabTask != nil || status == .copyingFrame || status == .savingFrame
    }

    var canExport: Bool {
        hasSource && !isExporting && isEditedPreviewReady
    }

    var canSaveOriginal: Bool {
        hasSource && !isExporting
    }

    var canDiscard: Bool {
        hasSource && !isExporting
    }

    var canGrabFrame: Bool {
        hasVideoSource && !isExporting && !isGrabbingFrame && player.rate == 0
    }

    var canCancelExport: Bool {
        isExporting && exportTask != nil
    }

    var canRetryExport: Bool {
        isRecoverableExportFailure
    }

    var canNavigateToOlderRecording: Bool {
        guard !isExporting,
            !isLoadingSource,
            let recordingNavigationIndex
        else {
            return false
        }

        return recordingNavigationIndex < recordingNavigationURLs.count - 1
    }

    var canNavigateToNewerRecording: Bool {
        guard !isExporting,
            !isLoadingSource,
            let recordingNavigationIndex
        else {
            return false
        }

        return recordingNavigationIndex > 0
    }

    var canUndoEditorChange: Bool {
        editorUndoStack.canUndo
    }

    var canRedoEditorChange: Bool {
        editorUndoStack.canRedo
    }

    var showsExportProgressPanel: Bool {
        isExporting || exportProgress != nil || exportedURL != nil || status == .canceled
            || isRecoverableExportFailure
    }

    var exportPanelTitle: String {
        switch status {
        case .exporting, .savingOriginal:
            exportProgressTitle
        case .exported, .exportedBatch, .saved:
            "Export Complete"
        case .copyingFrame, .savingFrame, .copiedFrame, .savedFrame:
            statusMessage
        case .canceled:
            "Export Canceled"
        case .failed:
            "Export Failed"
        case .discarded:
            "Recording Discarded"
        case .empty, .loading, .ready:
            exportProgressTitle
        }
    }

    var exportPanelMessage: String {
        switch status {
        case .exported(let url), .saved(let url):
            url.lastPathComponent
        case .exportedBatch(let urls):
            "\(urls.count) files exported"
        case .savingOriginal:
            "Copying the source recording without re-encoding."
        case .copyingFrame, .savingFrame, .copiedFrame, .savedFrame:
            statusMessage
        case .failed(let message):
            message
        case .canceled:
            "The export was canceled before the output file was finished."
        default:
            statusMessage
        }
    }

    var exportPanelSystemImage: String {
        switch status {
        case .exporting, .savingOriginal:
            "arrow.triangle.2.circlepath"
        case .exported, .exportedBatch, .saved:
            "checkmark.circle"
        case .copyingFrame:
            "doc.on.clipboard"
        case .savingFrame:
            "square.and.arrow.down"
        case .copiedFrame, .savedFrame:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
        case .discarded:
            "trash"
        case .failed:
            "exclamationmark.triangle"
        case .empty, .loading, .ready:
            "square.and.arrow.down"
        }
    }

}
