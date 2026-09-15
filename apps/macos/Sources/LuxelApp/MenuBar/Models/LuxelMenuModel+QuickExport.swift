import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func runQuickExport(recording: PastRecording, presetID: UUID) async -> RecordingStopAction? {
        let recording = await recordingAfterTitle(recording)
        lockRecordingPaths(for: recording.primaryMediaURL)
        let presetName =
            settings.exportPresets.first { $0.id == presetID }?.name ?? LuxelLocalization.string("Quick Export")
        quickExportTask?.cancel()

        let task = Task {
            try await performRecordingQuickExport(recording, presetID: presetID, presetName: presetName)
        }
        quickExportTask = task

        do {
            let result = try await task.value

            updateQuickExportRecordingState(.idle)
            quickExportTask = nil
            quickExportProgress = nil
            recordingHistoryService.recordExport(
                result.exportedMedia,
                presetName: result.preset.name,
                for: recording
            )
            refreshRecentRecordings()
            return .quickExported(result.exportedMedia.fileURL)
        } catch is CancellationError {
            updateQuickExportRecordingState(.idle)
            quickExportTask = nil
            quickExportProgress = nil
            return nil
        } catch {
            updateQuickExportRecordingState(.idle)
            quickExportTask = nil
            quickExportProgress = nil
            recordingActionErrorMessage = errorMessage(error)
            return nil
        }
    }

    private func performRecordingQuickExport(
        _ recording: PastRecording, presetID: UUID, presetName: String
    ) async throws -> QuickExportResult {
        let sourceBookmark = finalDirectoryBookmark(for: recording.primaryMediaURL)
        let outputBookmark =
            recording.bundleManifest?.organization == nil
            ? settings.recordingsDirectoryBookmark : sourceBookmark
        let presets = settings.exportPresets
        let root = settings.recordingsDirectory
        return try await withBookmarkedDirectoryAccess(
            outputDirectory: recording.primaryMediaURL.deletingLastPathComponent(),
            bookmark: sourceBookmark, service: directoryAccessService,
            revokedError: { _ in CocoaError(.fileReadNoPermission) },
            operation: { [self] _ in
                let result = try await quickExportService.runQuickExport(
                    recording: recording, presetID: presetID, presets: presets,
                    recordingsDirectory: root, recordingsDirectoryBookmark: outputBookmark,
                    progress: { [weak self] snapshot in
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            self?.updateQuickExportRecordingState(.exporting(snapshot))
                            self?.quickExportProgress = QuickExportProgressPresentation(
                                presetName: presetName, snapshot: snapshot)
                        }
                    }
                )
                try? RecordingDocumentStore().recordExport(
                    RecordingExport(
                        fileURL: result.exportedMedia.fileURL, format: result.exportedMedia.format,
                        date: Date(), presetName: result.preset.name), sourceURL: recording.primaryMediaURL)
                return result
            }
        )
    }

    func cancelQuickExport() {
        quickExportTask?.cancel()
        quickExportProgress = nil
        updateQuickExportRecordingState(.idle)
    }

    private func updateQuickExportRecordingState(_ state: RecordingMenuState) {
        switch recordingState {
        case .idle, .exporting: recordingState = state
        default: break
        }
    }
}
