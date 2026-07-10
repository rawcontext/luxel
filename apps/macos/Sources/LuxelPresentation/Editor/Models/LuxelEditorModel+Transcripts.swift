import AVFoundation
import Foundation
import LuxelCore
import OSLog

private let transcriptLogger = Logger(subsystem: "media.luxel.app", category: "transcripts")

extension LuxelEditorModel {
    var canTranscribeSource: Bool {
        source?.hasAudio == true
            && audioTranscriptService != nil
            && (transcriptEnginePreference() == .precision
                    || speechRecognitionAuthorizationService != nil)
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
            && transcriptEnginePreference() == .appleSpeech
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
        if transcriptEnginePreference() == .precision
            || speechRecognitionAuthorizationState == .authorized {
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
              transcriptEnginePreference() == .appleSpeech,
              let source,
              let speechRecognitionAuthorizationService,
              speechRecognitionAuthorizationState == .notDetermined
                || speechRecognitionAuthorizationState == .denied
        else {
            return
        }

        let sourceURL = source.fileURL
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = Task {
            [weak self, speechRecognitionAuthorizationService] in
            let authorizationState = await speechRecognitionAuthorizationService.requestAuthorization()
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
                        sourceContext: self?.transcriptSourceContext ?? .unknown)
                }
            }
        }
    }

    func prepareTranscriptExtraction(sourceContext: TranscriptSourceContext) {
        transcriptSourceContext = sourceContext
        guard canTranscribeSource, let source else {
            return
        }

        if transcriptEnginePreference() == .precision {
            speechRecognitionAuthorizationTask?.cancel()
            speechRecognitionAuthorizationTask = nil
            speechRecognitionAuthorizationState = nil
            scheduleTranscriptExtraction(sourceContext: sourceContext)
            return
        }
        guard let speechRecognitionAuthorizationService else { return }

        let sourceURL = source.fileURL
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = Task {
            [weak self, speechRecognitionAuthorizationService] in
            let authorizationState =
                await speechRecognitionAuthorizationService.currentAuthorizationState()
            await MainActor.run {
                guard !Task.isCancelled,
                      self?.source?.fileURL == sourceURL
                else {
                    return
                }

                self?.speechRecognitionAuthorizationTask = nil
                self?.speechRecognitionAuthorizationState = authorizationState
                if authorizationState == .authorized {
                    self?.scheduleTranscriptExtraction(sourceContext: sourceContext)
                }
            }
        }
    }

    func scheduleTranscriptExtraction(sourceContext: TranscriptSourceContext) {
        guard canTranscribeSource,
              let source,
              let audioTranscriptService,
              transcriptEnginePreference() == .precision
                || speechRecognitionAuthorizationState == .authorized
        else {
            return
        }

        let sourceURL = source.fileURL
        let speakerCountHint = selectedSpeakerCountHint
        transcriptTask?.cancel()
        transcriptFailureMessage = nil
        isTranscriptExtractionActive = true
        transcriptExtractionStartedAt = Date()
        startSpeakerModelStatePolling()
        transcriptTask = Task { [weak self, audioTranscriptService] in
            do {
                let transcript = try await audioTranscriptService.transcript(
                    for: AudioTranscriptRequest(
                        audioURL: sourceURL,
                        locale: .current,
                        sourceContext: sourceContext,
                        speakerCountHint: speakerCountHint
                    ))
                Self.logTranscriptResult(transcript)
                await MainActor.run {
                    guard !Task.isCancelled,
                          self?.source?.fileURL == sourceURL
                    else {
                        return
                    }

                    self?.transcript = transcript
                    self?.transcriptFailureMessage = nil
                    self?.appliedSpeakerCountHint = speakerCountHint
                    self?.isTranscriptExtractionActive = false
                    self?.transcriptExtractionStartedAt = nil
                    self?.transcriptTask = nil
                    self?.stopSpeakerModelStatePolling()
                }
            } catch {
                Self.logTranscriptFailure(error)
                await MainActor.run {
                    guard !Task.isCancelled,
                          self?.source?.fileURL == sourceURL
                    else {
                        return
                    }

                    self?.transcript = nil
                    self?.transcriptFailureMessage = error.localizedDescription
                    self?.isTranscriptExtractionActive = false
                    self?.transcriptExtractionStartedAt = nil
                    self?.transcriptTask = nil
                    self?.stopSpeakerModelStatePolling()
                }
            }
        }
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
        speechRecognitionAuthorizationState = nil
        stopSpeakerModelStatePolling()

        guard isTranscriptPanelVisible else { return }
        prepareTranscriptExtraction(sourceContext: transcriptSourceContext)
    }

    private static func logTranscriptResult(_ transcript: TurnSegmentedTranscript?) {
        if let transcript {
            transcriptLogger.info(
                "Transcript extraction succeeded with \(transcript.spans.count, privacy: .public) spans and \(transcript.turns.count, privacy: .public) turns"
            )
        } else {
            transcriptLogger.notice("Transcript extraction completed without a displayable transcript")
        }
    }

    private static func logTranscriptFailure(_ error: any Error) {
        transcriptLogger.error(
            "Transcript extraction hidden after failure: \(String(reflecting: type(of: error)), privacy: .public) \(error.localizedDescription, privacy: .private)"
        )
    }
}
