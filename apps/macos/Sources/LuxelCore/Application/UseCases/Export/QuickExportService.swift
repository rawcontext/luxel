import Foundation

@MainActor
public final class QuickExportService {
    private let metadataReader: any MediaMetadataReader
    private let exportService: ExportService
    private let fileWorkflowService: ExportedFileWorkflowService
    private let directoryAccessService: BookmarkedDirectoryAccessService?
    private let userNotifier: (any UserNotifier)?

    public init(
        metadataReader: any MediaMetadataReader,
        exportService: ExportService,
        fileWorkflowService: ExportedFileWorkflowService,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil,
        userNotifier: (any UserNotifier)? = nil
    ) {
        self.metadataReader = metadataReader
        self.exportService = exportService
        self.fileWorkflowService = fileWorkflowService
        self.directoryAccessService = directoryAccessService
        self.userNotifier = userNotifier
    }

    public func runQuickExport(
        recording: PastRecording,
        presetID: UUID,
        presets: [ExportPreset],
        recordingsDirectory: URL,
        recordingsDirectoryBookmark: BookmarkedDirectory? = nil,
        progress: ExportService.ProgressHandler? = nil
    ) async throws -> QuickExportResult {
        let preset = try preset(withID: presetID, in: presets)
        let source = try await metadataReader.readSourceMedia(at: recording.fileURL)
        let request = try preset.resolvedRequest(source: source)

        let exported = try await withOutputDirectoryAccess(
            outputDirectory: outputDirectory(for: preset, recordingsDirectory: recordingsDirectory),
            bookmark: outputDirectoryBookmark(
                for: preset, recordingsDirectoryBookmark: recordingsDirectoryBookmark)
        ) { outputDirectory in
            let exported = try await exportService.export(
                request,
                to: outputDirectory,
                defaultName: defaultExportName(recording: recording, preset: preset),
                progress: progress
            )

            try await performPostAction(
                preset.effectivePostAction,
                exportedURL: exported.fileURL,
                presetName: preset.name
            )
            return exported
        }

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

    private func outputDirectoryBookmark(
        for preset: ExportPreset,
        recordingsDirectoryBookmark: BookmarkedDirectory?
    ) -> BookmarkedDirectory? {
        switch preset.destination {
        case .recordingsDirectory, .clipboard:
            recordingsDirectoryBookmark
        case .folder:
            nil
        }
    }

    private func defaultExportName(recording: PastRecording, preset: ExportPreset) -> String {
        "\(recording.name) \(preset.name)"
    }

    private func withOutputDirectoryAccess<Result: Sendable>(
        outputDirectory: URL,
        bookmark: BookmarkedDirectory?,
        operation: @Sendable (URL) async throws -> Result
    ) async throws -> Result {
        guard let bookmark, let directoryAccessService else {
            return try await operation(outputDirectory)
        }

        let result = try await directoryAccessService.withAccess(to: bookmark) { directory in
            try await operation(directory.url)
        }

        guard let value = result.value else {
            throw QuickExportError.outputDirectoryAccessRevoked(result.directory.url)
        }

        return value
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
    case outputDirectoryAccessRevoked(URL)
}

extension QuickExportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .presetNotFound(let presetID):
            "Quick export preset \(presetID) was not found."
        case .notifierUnavailable:
            "Export notification delivery is unavailable."
        case .outputDirectoryAccessRevoked(let url):
            "Luxel no longer has permission to save to \(url.lastPathComponent). Choose the recordings folder again."
        }
    }
}
