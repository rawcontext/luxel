import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    func refreshRecordingNavigation(selectedFileURL: URL, outputDirectory: URL) {
        let selectedFileURL = selectedFileURL.standardizedFileURL
        recordingNavigationURLs = Self.recordingNavigationURLs(
            in: outputDirectory,
            selectedFileURL: selectedFileURL
        )
        recordingNavigationIndex = recordingNavigationURLs.firstIndex {
            $0.standardizedFileURL == selectedFileURL
        }
    }

    private static func recordingNavigationURLs(
        in outputDirectory: URL,
        selectedFileURL: URL
    ) -> [URL] {
        let directoryURLs =
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: [
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles]
            )) ?? []

        let recordingURLs =
            (directoryURLs.compactMap(recordingNavigationCandidate)
                + [
                    recordingNavigationCandidate(for: selectedFileURL)
                        ?? (selectedFileURL.standardizedFileURL, .distantPast)
                ])
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }

                return lhs.date > rhs.date
            }
            .map(\.url)

        return uniqueNavigationURLs(recordingURLs)
    }

    private static func recordingNavigationCandidate(for url: URL) -> (url: URL, date: Date)? {
        guard isNavigableRecordingURL(url),
              let values = try? url.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey
              ]),
              values.isRegularFile == true
        else {
            return nil
        }

        let date =
            [
                values.creationDate,
                values.contentModificationDate
            ].compactMap(\.self).max() ?? .distantPast

        return (url.standardizedFileURL, date)
    }

    private static func isNavigableRecordingURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "caf", "flac", "m4a", "m4v", "mov", "mp4", "wav":
            true
        default:
            false
        }
    }

    private static func uniqueNavigationURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []

        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    func makeExportJobs(for formats: [ExportFormat]) -> [ExportJobSnapshot] {
        formats.enumerated().map { index, format in
            ExportJobSnapshot(id: index, format: format)
        }
    }

    func updateExportJob(id: Int, snapshot: ExportProgressSnapshot) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].progress = snapshot
    }

    func updateExportJob(id: Int, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    func updateExportJob(format: ExportFormat, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.format == format }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    func revealExportJob(_ job: ExportJobSnapshot) {
        guard let fileURL = job.fileURL else {
            return
        }

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.revealInFinder(fileURL)
        }
    }

    var isRecoverableExportFailure: Bool {
        if case .failed = status {
            return hasSource
        }

        return false
    }

    func clampedPixelDimension(_ value: Int) -> Int {
        min(max(value, 1), 8192)
    }

    func updateSizePresetFromDimensions() {
        guard let source,
              let currentPixelSize = try? PixelSize(width: outputWidth, height: outputHeight)
        else {
            sizePreset = nil
            return
        }

        sizePreset = Self.sizePresets.first { preset in
            (try? preset.pixelSize(for: source.pixelSize)) == currentPixelSize
        }
    }

    func applySizePreset(_ preset: EditorSizePreset?) {
        sizePreset = preset

        guard let preset, let source else {
            return
        }

        do {
            let pixelSize = try preset.pixelSize(for: source.pixelSize)
            outputWidth = pixelSize.width
            outputHeight = pixelSize.height
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func applyFrameRate(_ value: Int) {
        frameRate = min(max(value, 1), maximumFrameRate)
    }

    func applyExportMemory(for format: ExportFormat) {
        guard let memory = exportMemoryByFormat[format] else {
            if !quality.isAvailable(for: format) {
                quality = ExportQuality.defaultQuality(for: format)
            }
            return
        }

        applySizePreset(memory.sizePreset)
        applyFrameRate(memory.frameRate.framesPerSecond)
        quality =
            memory.quality.isAvailable(for: format)
            ? memory.quality
            : ExportQuality.defaultQuality(for: format)
        if format == .gif || format == .apng, let gifOptions = memory.gifOptions {
            applyGIFOptions(gifOptions)
        }
    }

    func applySupportedFormatForSource() {
        format = preferredExportFormatForSource()
        selectedFormats = [format]
    }

    func applyGIFOptions(_ options: GIFRenderOptions) {
        gifDithering = options.dithering

        switch options.loopMode {
        case .forever:
            gifLoopModeKind = .forever
        case .none:
            gifLoopModeKind = .none
        case .count(let count):
            gifLoopModeKind = .count
            gifLoopCount = min(max(count, 1), 100)
        case .bounce:
            gifLoopModeKind = .bounce
        }
    }

    func renamedSourceURL(
        for sourceURL: URL,
        proposedFileName: String
    ) throws -> URL {
        var fileName = proposedFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else {
            throw EditorSourceRenameError.emptyFileName
        }
        guard !fileName.contains("/"),
              !fileName.contains("\u{0}"),
              fileName != ".",
              fileName != ".."
        else {
            throw EditorSourceRenameError.invalidFileName
        }

        if URL(fileURLWithPath: fileName).pathExtension.isEmpty,
           !sourceURL.pathExtension.isEmpty {
            fileName += ".\(sourceURL.pathExtension)"
        }

        return
            sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent(fileName)
            .standardizedFileURL
    }

    func withSourceDirectoryAccess<Result: Sendable>(
        for sourceURL: URL,
        operation: () throws -> Result
    ) throws -> Result {
        guard let outputDirectoryBookmark, let directoryAccessService else {
            return try operation()
        }

        let outputDirectoryPath = outputDirectory.standardizedFileURL.path
        guard sourceURL.standardizedFileURL.path.hasPrefix(outputDirectoryPath) else {
            return try operation()
        }

        let result = try directoryAccessService.withAccess(to: outputDirectoryBookmark) { _ in
            try operation()
        }
        guard let value = result.value else {
            throw EditorDirectoryAccessError.revoked(result.directory.url)
        }

        return value
    }

    func makeExportDraft(source: SourceMedia) throws -> EditorExportDraft {
        try EditorExportDraft(
            source: source,
            format: format,
            quality: quality,
            speed: playbackSpeed,
            gifOptions: try currentGIFOptions(for: format),
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            trimRange: TimeRange(start: trimStart, end: trimEnd),
            shouldCrop: hasVideoSource && shouldCrop,
            shouldMute: hasAudioOnlySource ? false : shouldMute,
            audioMix: currentAudioMixPlan(),
            studioVoiceEnabled: studioVoiceEnabled,
            keystrokeOptions: keystrokeOptions,
            editPlan: transcriptEditPlan
        )
    }

    func makeExportRequest(source: SourceMedia, format: ExportFormat) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: source.fileURL,
            format: format,
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            timeRange: TimeRange(start: trimStart, end: trimEnd),
            shouldMute: source.isAudioOnly ? false : shouldMute,
            audioMix: currentAudioMixPlan(),
            studioVoiceEnabled: studioVoiceEnabled,
            shouldCrop: source.hasVideo && shouldCrop,
            quality: quality,
            speed: playbackSpeed,
            editPlan: transcriptEditPlan,
            gifOptions: try currentGIFOptions(for: format),
            keystrokeOptions: keystrokeOptions
        )
    }

    func currentAudioMixPlan() -> AudioMixPlan? {
        guard includesAudio else {
            return nil
        }

        guard audioVolume != 1 || normalizeAudio else {
            return nil
        }

        return AudioMixPlan(
            tracks: [AudioTrackMix(kind: .system, volume: audioVolume)],
            normalizePeak: normalizeAudio
        )
    }

}

enum EditorSourceRenameError: LocalizedError, Equatable {
    case emptyFileName
    case invalidFileName
    case destinationExists(URL)

    var errorDescription: String? {
        switch self {
        case .emptyFileName:
            "Filename cannot be empty."
        case .invalidFileName:
            "Filename contains invalid characters."
        case .destinationExists(let url):
            "\(url.lastPathComponent) already exists."
        }
    }
}
