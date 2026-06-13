import Foundation

@MainActor
public final class QuickExportService {
    private let metadataReader: any MediaMetadataReader
    private let exportService: ExportService
    private let fileWorkflowService: ExportedFileWorkflowService
    private let userNotifier: (any UserNotifier)?

    public init(
        metadataReader: any MediaMetadataReader,
        exportService: ExportService,
        fileWorkflowService: ExportedFileWorkflowService,
        userNotifier: (any UserNotifier)? = nil
    ) {
        self.metadataReader = metadataReader
        self.exportService = exportService
        self.fileWorkflowService = fileWorkflowService
        self.userNotifier = userNotifier
    }

    public func runQuickExport(
        recording: PastRecording,
        presetID: UUID,
        presets: [ExportPreset],
        recordingsDirectory: URL,
        progress: ExportService.ProgressHandler? = nil
    ) async throws -> QuickExportResult {
        let preset = try preset(withID: presetID, in: presets)
        let source = try await metadataReader.readSourceMedia(at: recording.fileURL)
        let request = try preset.resolvedRequest(source: source)
        let exported = try await exportService.export(
            request,
            to: outputDirectory(for: preset, recordingsDirectory: recordingsDirectory),
            defaultName: defaultExportName(recording: recording, preset: preset),
            progress: progress
        )

        try await performPostAction(preset.effectivePostAction, exportedURL: exported.fileURL, presetName: preset.name)

        return QuickExportResult(
            recording: recording,
            preset: preset,
            exportedMedia: exported,
            postAction: preset.effectivePostAction
        )
    }

    private func preset(withID presetID: UUID, in presets: [ExportPreset]) throws -> ExportPreset {
        guard let preset = presets.first(where: { $0.id == presetID }) else {
            throw QuickExportError.presetNotFound(presetID)
        }

        return preset
    }

    private func outputDirectory(for preset: ExportPreset, recordingsDirectory: URL) -> URL {
        switch preset.destination {
        case .recordingsDirectory, .clipboard:
            recordingsDirectory
        case .folder(let folderURL):
            folderURL
        }
    }

    private func defaultExportName(recording: PastRecording, preset: ExportPreset) -> String {
        "\(recording.name) \(preset.name)"
    }

    private func performPostAction(
        _ postAction: ExportPresetPostAction,
        exportedURL: URL,
        presetName: String
    ) async throws {
        switch postAction {
        case .none:
            return
        case .revealInFinder:
            fileWorkflowService.revealInFinder(exportedURL)
        case .copyToClipboard:
            fileWorkflowService.copyFile(exportedURL)
        case .notifyWithThumbnail:
            guard let userNotifier else {
                throw QuickExportError.notifierUnavailable
            }

            try await userNotifier.notifyExportCompleted(fileURL: exportedURL, presetName: presetName)
        }
    }
}

public struct QuickExportResult: Equatable, Sendable {
    public let recording: PastRecording
    public let preset: ExportPreset
    public let exportedMedia: ExportedMedia
    public let postAction: ExportPresetPostAction

    public init(
        recording: PastRecording,
        preset: ExportPreset,
        exportedMedia: ExportedMedia,
        postAction: ExportPresetPostAction
    ) {
        self.recording = recording
        self.preset = preset
        self.exportedMedia = exportedMedia
        self.postAction = postAction
    }
}

public enum QuickExportError: Error, Equatable {
    case presetNotFound(UUID)
    case notifierUnavailable
}
