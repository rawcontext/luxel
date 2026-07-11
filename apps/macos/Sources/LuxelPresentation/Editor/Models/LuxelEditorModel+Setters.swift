import Foundation
import LuxelCore

extension LuxelEditorModel {
    func setFormat(_ nextFormat: ExportFormat) {
        guard supportedFormats.contains(nextFormat) else {
            return
        }

        format = nextFormat
        selectedFormats = [nextFormat]
        applyExportMemory(for: nextFormat)
        rememberLastSelectedExportFormat(nextFormat)

        if !canIncludeAudio {
            shouldMute = true
        }

        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setFormatSelection(_ nextFormat: ExportFormat, isSelected: Bool) {
        guard supportedFormats.contains(nextFormat) else {
            return
        }

        let previousFormat = format
        if isSelected {
            if !selectedFormats.contains(nextFormat) {
                selectedFormats.append(nextFormat)
                selectedFormats = supportedFormats.filter(selectedFormats.contains)
            }
            format = nextFormat
            applyExportMemory(for: nextFormat)
            rememberLastSelectedExportFormat(nextFormat)
        } else {
            guard selectedFormats.count > 1 else {
                return
            }

            selectedFormats.removeAll { $0 == nextFormat }
            if format == nextFormat, let replacement = selectedFormats.first {
                format = replacement
                applyExportMemory(for: replacement)
            }
            if format != previousFormat {
                rememberLastSelectedExportFormat(format)
            }
        }

        if !canIncludeAudio {
            shouldMute = true
        }

        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setQuality(_ nextQuality: ExportQuality) {
        guard nextQuality.isAvailable(for: format) else {
            quality = ExportQuality.defaultQuality(for: format)
            exportProgress = nil
            recordEditorDraftChange()
            return
        }

        quality = nextQuality
        exportProgress = nil
        recordEditorDraftChange()
    }

    func setGIFLoopModeKind(_ kind: EditorGIFLoopModeKind) {
        guard gifLoopModeKind != kind else {
            return
        }

        gifLoopModeKind = kind
        recordEditorDraftChange()
    }

    func setGIFLoopCount(_ count: Int) {
        let clampedCount = min(max(count, 1), 100)
        guard gifLoopCount != clampedCount else {
            return
        }

        gifLoopCount = clampedCount
        recordEditorDraftChange(coalescingToken: "gif-loop-count")
    }

    func setGIFDithering(_ dithering: GIFDitheringMode) {
        guard gifDithering != dithering else {
            return
        }

        gifDithering = dithering
        recordEditorDraftChange()
    }

    func setIncludesAudio(_ includesAudio: Bool) {
        if hasAudioOnlySource {
            shouldMute = false
            schedulePreviewAudioMixUpdate()
            return
        }

        shouldMute = !includesAudio
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setAudioVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 2)
        guard audioVolume != clampedVolume else {
            return
        }

        audioVolume = clampedVolume
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "audio-volume")
    }

    func setNormalizeAudio(_ normalize: Bool) {
        guard normalizeAudio != normalize else {
            return
        }

        normalizeAudio = normalize
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setStudioVoiceEnabled(_ enabled: Bool) {
        guard studioVoiceEnabled != enabled else {
            return
        }

        studioVoiceEnabled = enabled
        recordEditorDraftChange()
    }

    func setSizePreset(_ preset: EditorSizePreset?) {
        applySizePreset(preset)
        recordEditorDraftChange()
    }

    func setOutputWidth(_ value: Int) {
        outputWidth = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
        recordEditorDraftChange(coalescingToken: "output-width")
    }

    func setOutputHeight(_ value: Int) {
        outputHeight = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
        recordEditorDraftChange(coalescingToken: "output-height")
    }

    func setFrameRate(_ value: Int) {
        applyFrameRate(value)
        recordEditorDraftChange(coalescingToken: "frame-rate")
    }

    func setPlaybackSpeed(_ value: Double) {
        let clampedValue = min(max(value, 0.1), 10)
        guard let nextSpeed = try? PlaybackSpeed(clampedValue), nextSpeed != playbackSpeed else {
            return
        }

        playbackSpeed = nextSpeed
        applyPlaybackRateIfNeeded()
        recordEditorDraftChange(coalescingToken: "playback-speed")
    }

    func setTrimStart(_ value: TimeInterval) {
        let maxStart = max(0, min(duration - minimumTrimDuration, trimEnd - minimumTrimDuration))
        trimStart = min(max(value, 0), maxStart)
        seekPlaybackIntoTrimRangeIfNeeded()
        if !transcriptEditPlan.cuts.isEmpty {
            rebuildEditedPreview()
        }
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "trim-start")
    }

    func setTrimEnd(_ value: TimeInterval) {
        let minEnd = min(duration, trimStart + minimumTrimDuration)
        trimEnd = min(max(value, minEnd), duration)
        seekPlaybackIntoTrimRangeIfNeeded()
        if !transcriptEditPlan.cuts.isEmpty {
            rebuildEditedPreview()
        }
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "trim-end")
    }

    func setShouldCrop(_ shouldCrop: Bool) {
        self.shouldCrop = shouldCrop
        recordEditorDraftChange()
    }

    func updateKeystrokeOptions(
        isVisible: Bool? = nil,
        anchor: KeystrokeOverlayAnchor? = nil,
        size: KeystrokeOverlaySize? = nil,
        theme: KeystrokeOverlayTheme? = nil,
        displayDuration: TimeInterval? = nil
    ) {
        guard let current = keystrokeOptions,
              let updated = try? KeystrokeRenderOptions(
                isVisible: isVisible ?? current.isVisible,
                anchor: anchor ?? current.anchor,
                size: size ?? current.size,
                theme: theme ?? current.theme,
                displayDuration: displayDuration ?? current.displayDuration
              )
        else {
            return
        }
        keystrokeOptions = updated
        exportProgress = nil
    }

    func removeKeystrokeData() {
        guard let source else {
            return
        }
        do {
            _ = try KeystrokeSidecarRemovalService(fileSystem: fileSystem, mode: .delete)
                .remove(nextTo: source.fileURL)
            keystrokeTimeline = nil
            keystrokeOptions = nil
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func undoEditorChange() {
        guard let state = editorUndoStack.undo() else {
            return
        }

        applyEditorDraftState(state)
    }

    func redoEditorChange() {
        guard let state = editorUndoStack.redo() else {
            return
        }

        applyEditorDraftState(state)
    }

}
