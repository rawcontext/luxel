import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    public func open(
        fileURL: URL,
        outputDirectory: URL,
        outputDirectoryBookmark: BookmarkedDirectory? = nil,
        transcriptSourceContext: TranscriptSourceContext = .unknown
    ) async {
        prepareToOpen(
            fileURL: fileURL,
            outputDirectory: outputDirectory,
            outputDirectoryBookmark: outputDirectoryBookmark,
            transcriptSourceContext: transcriptSourceContext
        )

        do {
            let media = try await metadataReader.readSourceMedia(at: fileURL)
            applyOpenedMedia(
                media,
                fileURL: fileURL,
                transcriptSourceContext: transcriptSourceContext
            )
        } catch {
            applyOpenFailure(error)
        }
    }

    private func prepareToOpen(
        fileURL: URL,
        outputDirectory: URL,
        outputDirectoryBookmark: BookmarkedDirectory?,
        transcriptSourceContext: TranscriptSourceContext
    ) {
        self.outputDirectory = outputDirectory
        self.outputDirectoryBookmark = outputDirectoryBookmark
        refreshRecordingNavigation(selectedFileURL: fileURL, outputDirectory: outputDirectory)
        status = .loading(fileURL.lastPathComponent)
        exportProgress = nil
        exportJobs = []
        exportEstimatesByFormat = [:]
        estimatingExportSizeFormats = []
        player.pause()
        playbackRequested = false
        frameGrabTask?.cancel()
        frameGrabTask = nil
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        previewCompositionTask?.cancel()
        previewCompositionTask = nil
        transcript = nil
        transcriptEditPlan = .empty
        selectedTranscriptWordIDs = []
        transcriptWordSelectionAnchorID = nil
        transcriptEditStatusMessage = nil
        isEditedPreviewReady = true
        keystrokeTimeline = nil
        keystrokeOptions = nil
        isTranscriptExtractionActive = false
        isTranscriptPanelVisible = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        transcriptFailureMessage = nil
        speechRecognitionAuthorizationState = nil
        resetSpeakerCountControls()
        self.transcriptSourceContext = transcriptSourceContext
        currentPlaybackTime = 0
    }

    private func applyOpenedMedia(
        _ media: SourceMedia,
        fileURL: URL,
        transcriptSourceContext: TranscriptSourceContext
    ) {
        let resolvedTranscriptSourceContext = resolvedTranscriptSourceContext(
            transcriptSourceContext,
            for: media
        )
        source = media
        keystrokeTimeline = try? KeystrokeSidecarFileLoader().load(nextTo: fileURL)
        keystrokeOptions = keystrokeTimeline == nil ? nil : .standard
        self.transcriptSourceContext = resolvedTranscriptSourceContext
        applySupportedFormatForSource()
        trimStart = 0
        trimEnd = media.duration
        playbackSpeed = .normal
        applySizePreset(.original)
        applyFrameRate(Self.defaultFrameRate)
        applyExportMemory(for: format)
        shouldMute = media.isAudioOnly ? false : !media.hasAudio || format.dropsAudio
        studioVoiceEnabled = false
        let item = AVPlayerItem(url: fileURL)
        item.audioTimePitchAlgorithm = .timeDomain
        player.replaceCurrentItem(with: item)
        schedulePreviewAudioMixUpdate()
        status = .ready
        resetEditorUndoStack()
        isTranscriptPanelVisible = media.isAudioOnly
        if media.isAudioOnly {
            prepareTranscriptExtraction(sourceContext: resolvedTranscriptSourceContext)
        }
    }

    private func applyOpenFailure(_ error: Error) {
        source = nil
        studioVoiceEnabled = false
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        previewCompositionTask?.cancel()
        previewCompositionTask = nil
        transcript = nil
        transcriptEditPlan = .empty
        selectedTranscriptWordIDs = []
        transcriptWordSelectionAnchorID = nil
        transcriptEditStatusMessage = nil
        isEditedPreviewReady = true
        keystrokeTimeline = nil
        keystrokeOptions = nil
        isTranscriptExtractionActive = false
        isTranscriptPanelVisible = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        transcriptFailureMessage = nil
        speechRecognitionAuthorizationState = nil
        resetSpeakerCountControls()
        player.replaceCurrentItem(with: nil)
        status = .failed(errorMessage(error))
        resetEditorUndoStack()
    }

    private func resolvedTranscriptSourceContext(
        _ sourceContext: TranscriptSourceContext,
        for source: SourceMedia
    ) -> TranscriptSourceContext {
        guard sourceContext.recordingAudioMode == nil else {
            return sourceContext
        }

        let audioTracks = Set(source.audioTracks)
        switch (audioTracks.contains(.system), audioTracks.contains(.microphone)) {
        case (true, true):
            return TranscriptSourceContext(
                recordingAudioMode: .systemAndMicrophone(deviceID: nil))
        case (true, false):
            return TranscriptSourceContext(recordingAudioMode: .system)
        case (false, true):
            return TranscriptSourceContext(recordingAudioMode: .microphone(deviceID: nil))
        case (false, false):
            return .unknown
        }
    }

    public func configureExportMemory(
        _ memory: [ExportFormat: ExportMemory],
        onChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil
    ) {
        exportMemoryByFormat = memory
        onExportMemoryChange = onChange
        applyExportMemory(for: format)
        resetEditorUndoStack()
    }

    public func configureLastSelectedExportFormat(
        _ format: ExportFormat?,
        onChange: (@MainActor (ExportFormat) -> Void)? = nil
    ) {
        lastSelectedExportFormat = format
        onLastSelectedExportFormatChange = onChange
        applySupportedFormatForSource()
        applyExportMemory(for: self.format)
        resetEditorUndoStack()
    }

    public func configureDiscard(
        confirmDiscard: Bool,
        onDiscard: (@MainActor (URL) -> Void)? = nil,
        onConfirmDiscardChange: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.confirmDiscard = confirmDiscard
        self.onDiscardRecording = onDiscard
        self.onConfirmDiscardChange = onConfirmDiscardChange
    }

    public func configureSourceFileRename(
        onRename: (@MainActor (URL, URL) throws -> Void)? = nil
    ) {
        onSourceFileRenamed = onRename
    }

    func setConfirmDiscard(_ confirmDiscard: Bool) {
        guard self.confirmDiscard != confirmDiscard else {
            return
        }

        self.confirmDiscard = confirmDiscard
        onConfirmDiscardChange?(confirmDiscard)
    }

    public func reportImportFailure(_ error: Error) {
        source = nil
        exportProgress = nil
        exportEstimatesByFormat = [:]
        estimatingExportSizeFormats = []
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        previewCompositionTask?.cancel()
        previewCompositionTask = nil
        transcriptEditPlan = .empty
        selectedTranscriptWordIDs = []
        transcriptWordSelectionAnchorID = nil
        transcriptEditStatusMessage = nil
        isEditedPreviewReady = true
        player.replaceCurrentItem(with: nil)
        status = .failed(errorMessage(error))
        resetEditorUndoStack()
    }

    public func pausePlayback() {
        player.pause()
        playbackRequested = false
    }

}
