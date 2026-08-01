import AVFoundation
import Foundation
import LuxelCore
import OSLog

private let transcriptLogger = Logger(subsystem: "media.luxel.app", category: "transcripts")

extension LuxelEditorModel {
    var canTranscribeSource: Bool {
        source?.hasAudio == true
            && audioTranscriptService != nil
            && speechRecognitionAuthorizationService != nil
    }

    var canShowVideoTranscriptToggle: Bool {
        hasVideoSource && canTranscribeSource
    }

    var canCloseTranscriptPanel: Bool {
        hasVideoSource && isTranscriptPanelVisible
    }

    var visibleTranscript: TurnSegmentedTranscript? {
        isTranscriptPanelVisible && canTranscribeSource ? transcript : nil
    }

    var shouldShowSpeechRecognitionPrompt: Bool {
        isTranscriptPanelVisible
            && canTranscribeSource
            && (speechRecognitionAuthorizationState == .notDetermined
                    || speechRecognitionAuthorizationState == .denied)
    }

    var shouldShowTranscriptProgress: Bool {
        isTranscriptPanelVisible
            && canTranscribeSource
            && isTranscriptExtractionActive
            && visibleTranscript == nil
            && !shouldShowSpeechRecognitionPrompt
    }

    var shouldShowTranscriptFailure: Bool {
        isTranscriptPanelVisible && transcriptFailureMessage != nil
    }

    func seekToTranscriptTurn(_ turn: TranscriptTurn) {
        seekToTranscriptTime(turn.start)
    }

    func seekToTranscriptSpan(_ span: TimedTranscriptSpan) {
        seekToTranscriptTime(span.start)
    }

    func selectTranscriptWord(
        _ word: TranscriptEditableWord,
        extendingSelection: Bool = false,
        autoPlay: Bool = true
    ) {
        let words = visibleTranscriptWords
        guard let selectedIndex = cachedVisibleTranscriptWordIndexByID[word.id] else {
            return
        }

        if extendingSelection,
           let transcriptWordSelectionAnchorID,
           let anchorIndex = cachedVisibleTranscriptWordIndexByID[transcriptWordSelectionAnchorID] {
            selectedTranscriptWordIDs = Set(
                words[min(anchorIndex, selectedIndex)...max(anchorIndex, selectedIndex)].map(\.id)
            )
        } else {
            selectedTranscriptWordIDs = [word.id]
            transcriptWordSelectionAnchorID = word.id
        }
        transcriptEditStatusMessage = nil
        seekToTranscriptTime(word.sourceRange.start, autoPlay: autoPlay)
    }

    @discardableResult
    func deleteSelectedTranscriptWord() -> Bool {
        guard let transcript, !selectedTranscriptWordIDs.isEmpty else {
            return false
        }

        do {
            let trimRange = try TimeRange(start: trimStart, end: trimEnd)
            guard let cut = try TranscriptWordCutPlanner().cut(
                transcript: transcript,
                wordIDs: visibleTranscriptWords.compactMap {
                    selectedTranscriptWordIDs.contains($0.id) ? $0.id : nil
                },
                trimRange: trimRange,
                editPlan: transcriptEditPlan,
                minimumRetainedDuration: minimumTrimDuration
            ),
            let updatedPlan = try transcriptEditPlan.inserting(
                cut,
                within: trimRange,
                minimumRetainedDuration: minimumTrimDuration
            )
            else {
                transcriptEditStatusMessage = "That word is already cut."
                return false
            }

            transcriptEditPlan = updatedPlan
            let selectedCount = selectedTranscriptWordIDs.count
            selectedTranscriptWordIDs = []
            transcriptWordSelectionAnchorID = nil
            transcriptEditStatusMessage = selectedCount == 1
                ? "Word cut"
                : "\(selectedCount) words cut"
            exportEstimatesByFormat = [:]
            rebuildEditedPreview()
            recordEditorDraftChange()
            lastTranscriptCutID = cut.id
            return true
        } catch TimelineEditingError.insufficientRetainedDuration {
            transcriptEditStatusMessage = "Keep at least part of the recording."
        } catch {
            transcriptEditStatusMessage = "Could not cut that word."
        }
        return false
    }

    func undoLastTranscriptCut() {
        guard canUndoLastTranscriptCut else {
            return
        }
        undoEditorChange()
    }

    func restoreTranscriptCut(id: String) {
        guard transcriptEditPlan.cuts.contains(where: { $0.id == id }),
              let updatedPlan = try? TimelineEditPlan(
                cuts: transcriptEditPlan.cuts.filter { $0.id != id }
              )
        else {
            return
        }

        transcriptEditPlan = updatedPlan
        selectedTranscriptWordIDs = []
        transcriptWordSelectionAnchorID = nil
        exportEstimatesByFormat = [:]
        rebuildEditedPreview(successMessage: "Cut restored")
        recordEditorDraftChange()
    }

    func toggleTranscriptPanel() {
        if isTranscriptPanelVisible, hasVideoSource {
            hideTranscriptPanel()
        } else {
            showTranscriptPanel()
        }
    }

    func showTranscriptPanel() {
        guard canTranscribeSource else {
            return
        }

        isTranscriptPanelVisible = true
        guard transcript == nil, !isTranscriptExtractionActive else {
            return
        }

        transcriptFailureMessage = nil
        if speechRecognitionAuthorizationState == .authorized {
            scheduleTranscriptExtraction(sourceContext: transcriptSourceContext)
        } else {
            prepareTranscriptExtraction(sourceContext: transcriptSourceContext)
        }
    }

    func hideTranscriptPanel() {
        guard hasVideoSource else {
            return
        }

        isTranscriptPanelVisible = false
    }

    func enableSpeechRecognition() {
        guard canTranscribeSource,
              isTranscriptPanelVisible,
              let source,
              let speechRecognitionAuthorizationService,
              speechRecognitionAuthorizationState == .notDetermined
                || speechRecognitionAuthorizationState == .denied
        else {
            return
        }

        let sourceURL = source.fileURL
        scheduleSpeechAuthorizationUpdate(sourceURL: sourceURL) {
            await speechRecognitionAuthorizationService.requestAuthorization()
        }
    }

    func prepareTranscriptExtraction(sourceContext: TranscriptSourceContext) {
        transcriptSourceContext = sourceContext
        guard canTranscribeSource, let source else {
            return
        }

        guard let speechRecognitionAuthorizationService else { return }

        let sourceURL = source.fileURL
        scheduleSpeechAuthorizationUpdate(sourceURL: sourceURL, sourceContext: sourceContext) {
            await speechRecognitionAuthorizationService.currentAuthorizationState()
        }
    }

    private func scheduleSpeechAuthorizationUpdate(
        sourceURL: URL,
        sourceContext: TranscriptSourceContext? = nil,
        load: @escaping @Sendable () async -> SpeechRecognitionAuthorizationState
    ) {
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = Task { [weak self] in
            let authorizationState = await load()
            await MainActor.run {
                guard !Task.isCancelled,
                      self?.source?.fileURL == sourceURL
                else {
                    return
                }

                self?.speechRecognitionAuthorizationTask = nil
                self?.speechRecognitionAuthorizationState = authorizationState
                if authorizationState == .authorized {
                    self?.scheduleTranscriptExtraction(
                        sourceContext: sourceContext ?? self?.transcriptSourceContext ?? .unknown
                    )
                }
            }
        }
    }

    func scheduleTranscriptExtraction(sourceContext: TranscriptSourceContext) {
        guard canTranscribeSource,
              let source,
              let audioTranscriptService,
              speechRecognitionAuthorizationState == .authorized
        else {
            return
        }

        let sourceURL = source.fileURL
        let speakerCountHint = selectedSpeakerCountHint
        transcriptTask?.cancel()
        transcriptFailureMessage = nil
        isTranscriptExtractionActive = true
        transcriptExtractionStartedAt = Date()
        transcriptExtractionProgress = nil
        startSpeakerModelStatePolling()
        let progressHandler = transcriptProgressHandler(sourceURL: sourceURL)
        transcriptTask = Task { [weak self, audioTranscriptService] in
            do {
                let transcript = try await audioTranscriptService.transcript(
                    for: AudioTranscriptRequest(
                        audioURL: sourceURL,
                        locale: .current,
                        sourceContext: sourceContext,
                        speakerCountHint: speakerCountHint
                    ),
                    progress: progressHandler
                )
                Self.logTranscriptResult(transcript)
                await MainActor.run {
                    self?.applyTranscriptResult(
                        transcript,
                        sourceURL: sourceURL,
                        speakerCountHint: speakerCountHint
                    )
                }
            } catch {
                Self.logTranscriptFailure(error)
                await MainActor.run {
                    self?.applyTranscriptFailure(error, sourceURL: sourceURL)
                }
            }
        }
    }

    private func transcriptProgressHandler(
        sourceURL: URL
    ) -> SpeechTranscriptionProgressHandler {
        { [weak self] progress in
            Task { @MainActor in
                guard let self,
                      self.source?.fileURL == sourceURL,
                      self.isTranscriptExtractionActive
                else {
                    return
                }

                self.transcriptExtractionProgress = max(
                    self.transcriptExtractionProgress ?? 0,
                    progress.fractionCompleted
                )
            }
        }
    }

    private func applyTranscriptResult(
        _ transcript: TurnSegmentedTranscript?,
        sourceURL: URL,
        speakerCountHint: TranscriptSpeakerCountHint
    ) {
        guard !Task.isCancelled, source?.fileURL == sourceURL else { return }
        self.transcript = transcript
        transcriptFailureMessage = nil
        appliedSpeakerCountHint = speakerCountHint
        finishTranscriptExtraction()
    }

    private func applyTranscriptFailure(_ error: any Error, sourceURL: URL) {
        guard !Task.isCancelled, source?.fileURL == sourceURL else { return }
        transcript = nil
        transcriptFailureMessage = error.localizedDescription
        finishTranscriptExtraction()
    }

    private func finishTranscriptExtraction() {
        isTranscriptExtractionActive = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        transcriptTask = nil
        stopSpeakerModelStatePolling()
    }

    public func refreshTranscriptionConfiguration() {
        transcriptTask?.cancel()
        transcriptTask = nil
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = nil
        transcript = nil
        transcriptFailureMessage = nil
        isTranscriptExtractionActive = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        speechRecognitionAuthorizationState = nil
        stopSpeakerModelStatePolling()

        guard isTranscriptPanelVisible else { return }
        prepareTranscriptExtraction(sourceContext: transcriptSourceContext)
    }

    private static func logTranscriptResult(_ transcript: TurnSegmentedTranscript?) {
        if let transcript {
            let spanCount = transcript.spans.count
            let turnCount = transcript.turns.count
            transcriptLogger.info(
                "Transcript success: \(spanCount, privacy: .public) spans, \(turnCount, privacy: .public) turns"
            )
        } else {
            transcriptLogger.notice("Transcript extraction completed without a displayable transcript")
        }
    }

    private static func logTranscriptFailure(_ error: any Error) {
        let errorType = String(reflecting: type(of: error))
        transcriptLogger.error(
            "Transcript failure \(errorType, privacy: .public): \(error.localizedDescription, privacy: .private)"
        )
    }
}
