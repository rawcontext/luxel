import CoreMedia
import Foundation
import LuxelCore
import OSLog

private let speakersLogger = Logger(subsystem: "com.rawcontext.luxel", category: "speakers")

@MainActor
extension LuxelEditorModel {
    private static var speakerCountBounds: ClosedRange<Int> {
        1...12
    }

    var visibleSpeakerVoices: [DetectedSpeakerVoice] {
        detectedSpeakerVoices.filter { !ignoredSpeakerVoiceIDs.contains($0.id) }
    }

    var showsSpeakerCard: Bool {
        canTranscribeSource
            && isTranscriptPanelVisible
            && (transcript != nil
                    || isTranscriptExtractionActive
                    || hasPendingSpeakerCountHintChange)
    }

    var selectedSpeakerCountHint: TranscriptSpeakerCountHint {
        switch speakerCountMode {
        case .automatic:
            .automatic
        case .exact:
            .exact(exactSpeakerCount).normalized
        case .range:
            .range(min: minimumSpeakerCount, max: maximumSpeakerCount).normalized
        }
    }

    var hasPendingSpeakerCountHintChange: Bool {
        selectedSpeakerCountHint != appliedSpeakerCountHint
    }

    var canApplySpeakerCountHint: Bool {
        canTranscribeSource
            && isTranscriptPanelVisible
            && !isTranscriptExtractionActive
            && hasPendingSpeakerCountHintChange
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

    func setSpeakerCountMode(_ mode: EditorSpeakerCountMode) {
        guard speakerCountMode != mode else {
            return
        }

        speakerCountMode = mode
        switch mode {
        case .automatic:
            break
        case .exact:
            setExactSpeakerCount(inferredSpeakerCount())
        case .range:
            let detectedCount = inferredSpeakerCount()
            setMaximumSpeakerCount(max(detectedCount, detectedCount + 2))
            setMinimumSpeakerCount(detectedCount)
        }
    }

    func setExactSpeakerCount(_ count: Int) {
        exactSpeakerCount = clampedSpeakerCount(count)
    }

    func setMinimumSpeakerCount(_ count: Int) {
        let clamped = clampedSpeakerCount(count)
        minimumSpeakerCount = min(clamped, maximumSpeakerCount)
    }

    func setMaximumSpeakerCount(_ count: Int) {
        let clamped = clampedSpeakerCount(count)
        maximumSpeakerCount = max(clamped, minimumSpeakerCount)
    }

    func applySpeakerCountHint() {
        guard canTranscribeSource,
              isTranscriptPanelVisible
        else {
            return
        }

        transcriptTask?.cancel()
        transcriptTask = nil
        transcript = nil
        ignoredSpeakerVoiceIDs = []
        isTranscriptExtractionActive = false
        transcriptExtractionStartedAt = nil
        transcriptExtractionProgress = nil
        stopSpeakerModelStatePolling()

        if speechRecognitionAuthorizationState == .authorized {
            scheduleTranscriptExtraction(sourceContext: transcriptSourceContext)
        } else {
            prepareTranscriptExtraction(sourceContext: transcriptSourceContext)
        }
    }

    func resetSpeakerCountControls() {
        speakerCountMode = .automatic
        exactSpeakerCount = 1
        minimumSpeakerCount = 1
        maximumSpeakerCount = 3
        appliedSpeakerCountHint = .automatic
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
            sourceContext: transcriptSourceContext,
            speakerCountHint: appliedSpeakerCountHint
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

    func seekToTranscriptTime(_ time: TimeInterval, autoPlay: Bool = true) {
        currentPlaybackTime = time
        let shouldStartPlayback = autoPlay && !playbackRequested
        let playerTime = transcriptEditPlan.cuts.isEmpty
            ? time
            : previewOutputTime(forSourceTime: time)
        player.seek(
            to: CMTime(seconds: playerTime, preferredTimescale: 600),
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

    private func inferredSpeakerCount() -> Int {
        let visibleCount = visibleSpeakerVoices.count
        let transcriptCount = transcript?.speakers.count ?? 0
        return clampedSpeakerCount(max(visibleCount, transcriptCount, 1))
    }

    private func clampedSpeakerCount(_ count: Int) -> Int {
        min(max(count, Self.speakerCountBounds.lowerBound), Self.speakerCountBounds.upperBound)
    }
}
