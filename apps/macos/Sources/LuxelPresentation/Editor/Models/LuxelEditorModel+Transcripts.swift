import AVFoundation
import Foundation
import LuxelCore
import OSLog

private let transcriptLogger = Logger(subsystem: "media.luxel.app", category: "transcripts")

extension LuxelEditorModel {
    func seekToTranscriptTurn(_ turn: TranscriptTurn) {
        seekToTranscriptTime(turn.start)
    }

    func seekToTranscriptSpan(_ span: TimedTranscriptSpan) {
        seekToTranscriptTime(span.start)
    }

    private func seekToTranscriptTime(_ time: TimeInterval) {
        currentPlaybackTime = time
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func enableSpeechRecognition() {
        guard hasAudioOnlySource,
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
        guard hasAudioOnlySource,
              let source,
              audioTranscriptService != nil,
              let speechRecognitionAuthorizationService
        else {
            return
        }

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
        guard hasAudioOnlySource,
              let source,
              let audioTranscriptService,
              speechRecognitionAuthorizationState == .authorized
        else {
            return
        }

        let sourceURL = source.fileURL
        transcriptTask?.cancel()
        transcriptTask = Task { [weak self, audioTranscriptService] in
            do {
                let transcript = try await audioTranscriptService.transcript(
                    for: AudioTranscriptRequest(
                        audioURL: sourceURL,
                        locale: .current,
                        sourceContext: sourceContext
                    ))
                Self.logTranscriptResult(transcript)
                await MainActor.run {
                    guard !Task.isCancelled,
                          self?.source?.fileURL == sourceURL
                    else {
                        return
                    }

                    self?.transcript = transcript
                    self?.transcriptTask = nil
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
                    self?.transcriptTask = nil
                }
            }
        }
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
