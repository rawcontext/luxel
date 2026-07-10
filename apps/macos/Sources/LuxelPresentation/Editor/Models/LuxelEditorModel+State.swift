import AVKit
import Foundation
import LuxelCore

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
        formatTime(max(minimumTrimDuration, trimEnd - trimStart) / playbackSpeed.value)
    }

    var activeTranscriptTurnID: String? {
        visibleTranscript?.turns.first {
            $0.start <= currentPlaybackTime && currentPlaybackTime < $0.end
        }?.id
    }

    var activeTranscriptSpanID: String? {
        visibleTranscript?.spans.first {
            $0.start <= currentPlaybackTime && currentPlaybackTime < $0.end
        }?.id
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
        hasSource && !isExporting
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
