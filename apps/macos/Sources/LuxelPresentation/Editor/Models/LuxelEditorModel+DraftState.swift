import Foundation
import LuxelCore

extension LuxelEditorModel {
    func recordEditorDraftChange(coalescingToken: String? = nil) {
        guard hasSource else {
            return
        }

        editorUndoStack.push(currentEditorDraftState, coalescingToken: coalescingToken)
        exportProgress = nil
    }

    var currentEditorDraftState: EditorDraftState {
        EditorDraftState(
            format: format,
            selectedFormats: selectedFormats,
            trimStart: trimStart,
            trimEnd: trimEnd,
            sizePreset: sizePreset,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            frameRate: frameRate,
            playbackSpeed: playbackSpeed,
            shouldMute: shouldMute,
            audioVolume: audioVolume,
            normalizeAudio: normalizeAudio,
            shouldCrop: shouldCrop,
            quality: quality,
            gifLoopModeKind: gifLoopModeKind,
            gifLoopCount: gifLoopCount,
            gifDithering: gifDithering
        )
    }

    func resetEditorUndoStack() {
        editorUndoStack = UndoStack(initialState: currentEditorDraftState)
    }

    func applyEditorDraftState(_ state: EditorDraftState) {
        let fallbackFormat = supportedFormats.first ?? .mp4
        let restoredFormat = supportedFormats.contains(state.format) ? state.format : fallbackFormat
        let restoredFormats = supportedFormats.filter(state.selectedFormats.contains)

        format = restoredFormat
        selectedFormats = restoredFormats.isEmpty ? [restoredFormat] : restoredFormats
        if !selectedFormats.contains(format) {
            format = selectedFormats.first ?? fallbackFormat
        }
        trimStart = state.trimStart
        trimEnd = state.trimEnd
        sizePreset = state.sizePreset
        outputWidth = state.outputWidth
        outputHeight = state.outputHeight
        frameRate = min(max(state.frameRate, 1), maximumFrameRate)
        playbackSpeed = state.playbackSpeed
        applyPlaybackRateIfNeeded()
        quality =
            state.quality.isAvailable(for: format)
            ? state.quality
            : ExportQuality.defaultQuality(for: format)
        gifLoopModeKind = state.gifLoopModeKind
        gifLoopCount = min(max(state.gifLoopCount, 1), 100)
        gifDithering = state.gifDithering
        shouldMute = state.shouldMute
        if hasAudioOnlySource {
            shouldMute = false
        }
        if !canIncludeAudio {
            shouldMute = true
        }
        audioVolume = min(max(state.audioVolume, 0), 2)
        normalizeAudio = state.normalizeAudio
        shouldCrop = state.shouldCrop
        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        seekPlaybackIntoTrimRangeIfNeeded()
    }

    func currentExportMemory(for format: ExportFormat) throws -> ExportMemory {
        ExportMemory(
            sizePreset: sizePreset ?? .original,
            frameRate: try FrameRate(frameRate),
            quality: quality.isAvailable(for: format)
                ? quality : ExportQuality.defaultQuality(for: format),
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    func rememberExportMemory(_ memory: ExportMemory, for format: ExportFormat) {
        exportMemoryByFormat[format] = memory
        onExportMemoryChange?(format, memory)
    }

    func rememberLastSelectedExportFormat(_ format: ExportFormat) {
        guard lastSelectedExportFormat != format else {
            return
        }

        lastSelectedExportFormat = format
        onLastSelectedExportFormatChange?(format)
    }

    func preferredExportFormatForSource() -> ExportFormat {
        if hasAudioOnlySource {
            if let lastSelectedExportFormat,
               supportedFormats.contains(lastSelectedExportFormat) {
                return lastSelectedExportFormat
            }
            return supportedFormats.first ?? .m4a
        }

        return Self.preferredVideoExportFormat(
            from: supportedFormats,
            lastSelectedExportFormat: lastSelectedExportFormat
        )
    }

    static func preferredVideoExportFormat(
        from supportedFormats: [ExportFormat],
        lastSelectedExportFormat: ExportFormat?
    ) -> ExportFormat {
        if let lastSelectedExportFormat,
           supportedFormats.contains(lastSelectedExportFormat) {
            return lastSelectedExportFormat
        }
        if supportedFormats.contains(.webm) {
            return .webm
        }
        if supportedFormats.contains(.mp4) {
            return .mp4
        }

        return supportedFormats.first ?? .mp4
    }
}
