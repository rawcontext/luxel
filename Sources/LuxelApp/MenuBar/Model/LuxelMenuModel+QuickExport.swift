import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func runQuickExport(recording: PastRecording, presetID: UUID) async -> RecordingStopAction? {
        do {
            let result = try await quickExportService.runQuickExport(
                recording: recording,
                presetID: presetID,
                presets: settings.exportPresets,
                recordingsDirectory: settings.recordingsDirectory
            ) { [weak self] snapshot in
                await MainActor.run {
                    self?.recordingState = .exporting(snapshot)
                }
            }

            recordingState = .idle
            recentRecordings = Array(recordingHistoryService.recordExport(
                result.exportedMedia,
                presetName: result.preset.name,
                for: recording
            ).prefix(5))
            quickExportStatusMessage = quickExportStatusText(for: result.exportedMedia)
            return .quickExported(result.exportedMedia.fileURL)
        } catch {
            recordingState = .idle
            recordingActionErrorMessage = errorMessage(error)
            return nil
        }
    }

    private func quickExportStatusText(for exportedMedia: ExportedMedia) -> String {
        let fileName = exportedMedia.fileURL.lastPathComponent

        guard let fileSizeBytes = exportedMedia.fileSizeBytes else {
            return "Exported \(fileName)"
        }

        let fileSize = ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        return "Exported \(fileName) (\(fileSize))"
    }
}
