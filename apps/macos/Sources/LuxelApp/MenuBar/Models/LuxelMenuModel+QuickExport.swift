import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func runQuickExport(recording: PastRecording, presetID: UUID) async -> RecordingStopAction? {
        let presetName = settings.exportPresets.first { $0.id == presetID }?.name ?? "Quick Export"
        quickExportTask?.cancel()

        let task = Task {
            try await quickExportService.runQuickExport(
                recording: recording,
                presetID: presetID,
                presets: settings.exportPresets,
                recordingsDirectory: settings.recordingsDirectory
            ) { [weak self] snapshot in
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self?.recordingState = .exporting(snapshot)
                    self?.quickExportProgress = QuickExportProgressPresentation(
                        presetName: presetName,
                        snapshot: snapshot
                    )
                }
            }
        }
        quickExportTask = task

        do {
            let result = try await task.value

            recordingState = .idle
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
            recordingState = .idle
            quickExportTask = nil
            quickExportProgress = nil
            return nil
        } catch {
            recordingState = .idle
            quickExportTask = nil
            quickExportProgress = nil
            recordingActionErrorMessage = errorMessage(error)
            return nil
        }
    }

    func cancelQuickExport() {
        quickExportTask?.cancel()
        quickExportProgress = nil
        recordingState = .idle
    }
}
