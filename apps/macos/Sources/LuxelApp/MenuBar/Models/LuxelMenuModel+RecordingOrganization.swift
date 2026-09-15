import AppKit
import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    var automaticRecordingTitlesEnabled: Bool {
        RecordingTitlePolicy.isEnabled(
            preference: settings.automaticRecordingTitles, availability: recordingTitleModelAvailability)
    }

    func refreshRecordingTitleModel() {
        recordingTitleModelAvailability = recordingTitleGenerator.availability
    }

    func setAutomaticRecordingTitles(_ enabled: Bool) {
        settings.automaticRecordingTitles = enabled
        saveSettings()
        refreshRecordingTitleModel()
        if enabled && recordingTitleModelAvailability != .available { openAppleIntelligenceSetup() }
    }

    func openAppleIntelligenceSetup() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension"),
            NSWorkspace.shared.open(url) {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func prepareOrganizedRecording(_ original: PastRecording, captureKind: String) async -> PastRecording {
        let application = recordingSourceApplications.removeValue(forKey: original.fileURL)
        do {
            return try await withRecordingFolderAccess(original) { [self] in
                let recording = try RecordingDocumentStore().create(
                    for: original, captureKind: captureKind, sourceApplication: application)
                recordingHistoryService.replaceRecording(recording, previousURL: original.fileURL)
                refreshRecordingTitleModel()
                if automaticRecordingTitlesEnabled && recordingTitleModelAvailability == .available {
                    startRecordingTitleGeneration(recording)
                } else {
                    try? RecordingDocumentStore().lockPaths(nextTo: recording.primaryMediaURL)
                }
                refreshRecentRecordings()
                return recording
            }
        } catch { return original }
    }

    private func startRecordingTitleGeneration(_ recording: PastRecording) {
        guard let organization = recording.bundleManifest?.organization,
            organization.titleOrigin == .context, !organization.pathsLocked,
            recordingTitleTasks[organization.id] == nil
        else { return }
        let id = organization.id
        let (prefixes, continuation) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
        preparingRecordingIDs.insert(id)
        RecordingDocumentStore.setTitlePending(true, id: id)
        recordingTitleTasks[id] = Task { [weak self] in
            for await prefix in prefixes {
                if !prefix.isEmpty { await self?.applyGeneratedRecordingTitle(prefix: prefix, recording: recording) }
                break
            }
            self?.finishRecordingTitle(recording)
        }
        recordingTranscriptTasks[id] = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }
            do {
                try await withRecordingFolderAccess(recording) { [self] in
                    await streamRecordingTranscript(recording, continuation: continuation)
                }
            } catch { continuation.finish() }
            recordingTranscriptTasks[id] = nil
        }
    }

    private func streamRecordingTranscript(
        _ recording: PastRecording, continuation: AsyncStream<String>.Continuation
    ) async {
        defer { continuation.finish() }
        guard await AppleSpeechAuthorizationService().currentAuthorizationState() == .authorized else { return }
        let url = RecordingDocumentStore.currentMediaURL(for: recording.primaryMediaURL)
        let context = TranscriptSourceContext(recordingAudioMode: recording.options.audio)
        let locale = Locale(identifier: settings.transcriptLanguageIdentifier ?? Locale.current.identifier)
        do {
            if let source = try? await AVFoundationMediaMetadataReader().readSourceMedia(at: url) {
                _ = try? RecordingDocumentStore().update(nextTo: url) { $0.duration = source.duration }
            }
            let layout = try await AVFoundationAudioTrackInspector().audioTrackLayout(in: url)
            let trigger = TranscriptTitleTrigger(
                trackIDs: context.extractionPlans(audioTrackLayout: layout).map(\.audioTrackIndex),
                localeIdentifier: locale.identifier,
                onReady: { prefix in
                    continuation.yield(prefix)
                    continuation.finish()
                }
            )
            let service = LuxelCompositionRoot.localAudioTranscriptService(
                turnSegmentationModeOverride: .raw, speakerDiarizationModeOverride: .disabled,
                transcriptLocaleOverride: { locale },
                onTranscriptUpdate: { request, spans, completed in
                    trigger.receive(trackID: request.audioTrackIndex, spans: spans, completed: completed)
                }
            )
            if let transcript = try await service.transcript(
                for: AudioTranscriptRequest(audioURL: url, sourceContext: context)) {
                continuation.yield(RecordingTitlePolicy.transcriptPrefix(transcript))
            }
        } catch { return }
        refreshRecentRecordings()
    }

    private func applyGeneratedRecordingTitle(prefix: String, recording: PastRecording) async {
        guard automaticRecordingTitlesEnabled,
            (try? RecordingDocumentStore().load(nextTo: recording.primaryMediaURL))?.manifest.organization?.titleOrigin
                == .context
        else { return }
        do {
            let title = try await recordingTitleGenerator.title(from: prefix)
            guard automaticRecordingTitlesEnabled else { return }
            try await withRecordingFolderAccess(recording) { [self] in
                let updated = try RecordingDocumentStore().applyingAutomaticTitle(title, to: recording)
                recordingHistoryService.replaceRecording(updated, previousURL: recording.fileURL)
                configuredEditorModel?.applyAutomaticRecordingRename(
                    from: recording.primaryMediaURL, to: updated.primaryMediaURL)
                refreshRecentRecordings()
            }
        } catch { return }
    }

    private func finishRecordingTitle(_ recording: PastRecording) {
        guard let id = recording.bundleManifest?.organization?.id else { return }
        preparingRecordingIDs.remove(id)
        RecordingDocumentStore.setTitlePending(false, id: id)
        let url = RecordingDocumentStore.currentMediaURL(for: recording.primaryMediaURL)
        configuredEditorModel?.refreshAutomaticTitleState(for: url)
        recordingTitleTasks[id] = nil
        refreshRecentRecordings()
    }

    func prepareTitleForTranscription(of url: URL) {
        refreshRecordingTitleModel()
        guard automaticRecordingTitlesEnabled, recordingTitleModelAvailability == .available,
            let id = RecordingDocumentStore.identifier(for: url),
            let recording = recordingHistoryService.recording(withID: id)
        else { return }
        startRecordingTitleGeneration(recording)
    }

    func cancelAutomaticRecordingTitle(for url: URL) {
        guard let id = RecordingDocumentStore.identifier(for: url) else { return }
        recordingTitleTasks[id]?.cancel()
        recordingTitleTasks[id] = nil
        preparingRecordingIDs.remove(id)
        RecordingDocumentStore.setTitlePending(false, id: id)
        configuredEditorModel?.refreshAutomaticTitleState(for: url)
    }

    func recordingAfterTitle(_ recording: PastRecording) async -> PastRecording {
        guard let id = recording.bundleManifest?.organization?.id else { return recording }
        if let task = recordingTitleTasks[id] { await task.value }
        return recordingHistoryService.recording(withID: id) ?? recording
    }

    private func withRecordingFolderAccess<Value: Sendable>(
        _ recording: PastRecording, operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let url = RecordingDocumentStore.currentMediaURL(for: recording.primaryMediaURL)
        return try await withBookmarkedDirectoryAccess(
            outputDirectory: url.deletingLastPathComponent(), bookmark: finalDirectoryBookmark(for: url),
            service: directoryAccessService, revokedError: { _ in CocoaError(.fileWriteNoPermission) },
            operation: { _ in try await operation() }
        )
    }

    func lockRecordingPaths(for mediaURL: URL) {
        if let bookmark = finalDirectoryBookmark(for: mediaURL) {
            _ = try? directoryAccessService.withAccess(to: bookmark) { _ in
                try RecordingDocumentStore().lockPaths(nextTo: mediaURL)
            }
        } else {
            try? RecordingDocumentStore().lockPaths(nextTo: mediaURL)
        }
    }
}
