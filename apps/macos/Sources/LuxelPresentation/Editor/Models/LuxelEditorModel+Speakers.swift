import CoreMedia
import Foundation
import LuxelCore
import OSLog

private let speakersLogger = Logger(subsystem: "media.luxel.app", category: "speakers")

@MainActor
extension LuxelEditorModel {
    var visibleSpeakerVoices: [DetectedSpeakerVoice] {
        detectedSpeakerVoices.filter { !ignoredSpeakerVoiceIDs.contains($0.id) }
    }

    func refreshDetectedSpeakerVoices() {
        guard let transcript, !transcript.speakers.isEmpty,
              let speakerNamingService,
              let source
        else {
            detectedSpeakerVoices = []
            knownSpeakerOptions = []
            return
        }

        detectedSpeakerVoices = speakerNamingService.detectedVoices(
            transcript: transcript,
            audioURL: source.fileURL
        )
        knownSpeakerOptions = (try? speakerNamingService.knownSpeakers())?.profiles ?? []
    }

    func speakerAccentIndex(for speakerID: String?) -> Int? {
        guard let speakerID,
              let index = transcript?.speakers.firstIndex(where: { $0.id == speakerID })
        else {
            return nil
        }

        return index
    }

    func playSpeakerExample(_ range: SpeakerVoiceExampleRange) {
        exampleClipPlaybackTask?.cancel()
        seekToTranscriptTime(range.start)
        exampleClipPlaybackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(range.duration))
            guard !Task.isCancelled else {
                return
            }

            self?.pausePlayback()
        }
    }

    func saveDetectedVoiceAsKnownSpeaker(speakerID: String, name: String) {
        guard let transcript, let source, let speakerNamingService else {
            return
        }

        let audioURL = source.fileURL
        Task { [weak self] in
            do {
                let result = try await speakerNamingService.saveAsNewKnownSpeaker(
                    named: name,
                    speakerID: speakerID,
                    transcript: transcript,
                    audioURL: audioURL
                )
                self?.applyUpdatedTranscript(result.transcript, audioURL: audioURL)
            } catch {
                speakersLogger.error(
                    "Saving known speaker failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    func attachDetectedVoice(speakerID: String, toKnownSpeakerWithID profileID: UUID) {
        guard let transcript, let source, let speakerNamingService else {
            return
        }

        let audioURL = source.fileURL
        Task { [weak self] in
            do {
                let updated = try await speakerNamingService.attach(
                    speakerID: speakerID,
                    toProfileWithID: profileID,
                    transcript: transcript,
                    audioURL: audioURL
                )
                self?.applyUpdatedTranscript(updated, audioURL: audioURL)
            } catch {
                speakersLogger.error(
                    "Attaching known speaker failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    func resetDetectedVoiceMatch(speakerID: String) {
        guard let transcript, let source, let speakerNamingService else {
            return
        }

        do {
            let updated = try speakerNamingService.resetToAnonymous(
                speakerID: speakerID,
                transcript: transcript
            )
            applyUpdatedTranscript(updated, audioURL: source.fileURL)
        } catch {
            speakersLogger.error(
                "Resetting speaker match failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    func ignoreDetectedVoice(speakerID: String) {
        // Session-scoped: hides the voice for this recording without touching
        // the library or the transcript labels.
        ignoredSpeakerVoiceIDs.insert(speakerID)
    }

    private func applyUpdatedTranscript(_ updated: TurnSegmentedTranscript, audioURL: URL) {
        guard source?.fileURL == audioURL else {
            return
        }

        transcript = updated
        guard let audioTranscriptService else {
            return
        }

        let request = AudioTranscriptRequest(
            audioURL: audioURL,
            locale: .current,
            sourceContext: transcriptSourceContext
        )
        Task {
            do {
                try await audioTranscriptService.storeUpdatedTranscript(updated, for: request)
            } catch {
                speakersLogger.error(
                    "Persisting updated transcript failed: \(error.localizedDescription, privacy: .private)"
                )
            }
        }
    }

    func startSpeakerModelStatePolling() {
        speakerModelStatePollingTask?.cancel()
        guard let speakerModelStore else {
            isSpeakerModelPreparing = false
            return
        }

        speakerModelStatePollingTask = Task { [weak self, speakerModelStore] in
            while !Task.isCancelled {
                let isPreparing = await speakerModelStore.currentState().isPreparing
                await MainActor.run {
                    self?.isSpeakerModelPreparing = isPreparing
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopSpeakerModelStatePolling() {
        speakerModelStatePollingTask?.cancel()
        speakerModelStatePollingTask = nil
        isSpeakerModelPreparing = false
    }

    func seekToTranscriptTime(_ time: TimeInterval) {
        currentPlaybackTime = time
        let shouldStartPlayback = !playbackRequested
        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            guard finished, shouldStartPlayback else {
                return
            }

            Task { @MainActor in
                self?.startPlayback()
            }
        }
    }
}
