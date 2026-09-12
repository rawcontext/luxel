import AVKit
import Foundation
import LuxelCore

extension LuxelEditorModel {
    func schedulePreviewAudioMixUpdate() {
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil

        guard let source,
            let playerItem = player.currentItem
        else {
            player.isMuted = true
            player.currentItem?.audioMix = nil
            return
        }

        player.isMuted = !includesAudio
        guard includesAudio else {
            playerItem.audioMix = nil
            return
        }

        guard audioVolume != 1 || normalizeAudio else {
            playerItem.audioMix = nil
            return
        }

        let taskID = currentPreviewAudioMixTaskID(source: source)
        let request: ExportRequest
        do {
            request = try makeExportRequest(source: source, format: format)
        } catch {
            playerItem.audioMix = nil
            return
        }
        let sourceAudioTracks = source.audioTracks

        previewAudioMixTask = Task { [weak self] in
            await self?.resolvePreviewAudioMix(
                request: request,
                source: source,
                sourceAudioTracks: sourceAudioTracks,
                playerItem: playerItem,
                taskID: taskID
            )
        }
    }

    private func resolvePreviewAudioMix(
        request: ExportRequest,
        source: SourceMedia,
        sourceAudioTracks: [AudioTrackKind],
        playerItem: AVPlayerItem,
        taskID: PreviewAudioMixTaskID
    ) async {
        do {
            try await Task.sleep(for: .milliseconds(200))
            let gains = try await audioMixResolutionService.resolvedGains(
                for: request,
                sourceAudioTracks: sourceAudioTracks
            )
            let audioMix = try await makePreviewAudioMix(
                for: playerItem,
                gain: gains[.system] ?? 1
            )
            guard !Task.isCancelled,
                currentPreviewAudioMixTaskID(source: source) == taskID,
                player.currentItem === playerItem
            else {
                return
            }
            playerItem.audioMix = audioMix
            previewAudioMixTask = nil
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, player.currentItem === playerItem else { return }
            playerItem.audioMix = nil
            previewAudioMixTask = nil
        }
    }

    func makePreviewAudioMix(
        for playerItem: AVPlayerItem,
        gain: Double
    ) async throws -> AVAudioMix? {
        let audioTracks = try await playerItem.asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            return nil
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { audioTrack in
            let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
            parameters.audioTimePitchAlgorithm = .timeDomain
            parameters.setVolume(Float(gain), at: .zero)
            return parameters
        }
        return audioMix
    }

    func currentPreviewAudioMixTaskID(source: SourceMedia) -> PreviewAudioMixTaskID {
        PreviewAudioMixTaskID(
            sourceFileURL: source.fileURL,
            format: format,
            trimStart: trimStart,
            trimEnd: trimEnd,
            shouldMute: shouldMute,
            audioVolume: audioVolume,
            normalizeAudio: normalizeAudio
        )
    }

    func currentGIFOptions(for format: ExportFormat) throws -> GIFRenderOptions? {
        guard format == .gif || format == .apng else {
            return nil
        }

        if format == .apng {
            return try GIFRenderOptions(loopMode: gifLoopMode)
        }

        let resolvedQuality =
            quality.isAvailable(for: format)
            ? quality
            : ExportQuality.defaultQuality(for: format)
        return try GIFRenderOptions(
            quality: resolvedQuality,
            loopMode: gifLoopMode,
            dithering: gifDithering
        )
    }

    func applyPlaybackRateIfNeeded() {
        guard playbackRequested else {
            return
        }

        player.rate = Float(playbackSpeed.value)
    }

    func errorMessage(_ error: Error) -> String {
        errorReporter.record(error, context: "editor")
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }

    func withCurrentOutputDirectoryAccess(_ operation: () -> Void) {
        guard let outputDirectoryBookmark, let directoryAccessService else {
            operation()
            return
        }

        let result = directoryAccessService.withAccess(to: outputDirectoryBookmark) { _ in
            operation()
            return true
        }

        if result.value == nil {
            status = .failed(errorMessage(EditorDirectoryAccessError.revoked(result.directory.url)))
        }
    }
}

func withExportDirectoryAccess<Result: Sendable>(
    outputDirectory: URL,
    bookmark: BookmarkedDirectory?,
    directoryAccessService: BookmarkedDirectoryAccessService?,
    operation: @Sendable (URL) async throws -> Result
) async throws -> Result {
    try await withBookmarkedDirectoryAccess(
        outputDirectory: outputDirectory,
        bookmark: bookmark,
        service: directoryAccessService,
        revokedError: EditorDirectoryAccessError.revoked,
        operation: operation
    )
}

func editorBatchOutputDirectory(defaultName: String, in outputDirectory: URL) -> URL {
    outputDirectory.appending(path: defaultName, directoryHint: .isDirectory)
}

func editorOriginalOutputURL(for fileURL: URL, in outputDirectory: URL) -> URL {
    let baseName = "\(fileURL.deletingPathExtension().lastPathComponent) Original"
    let fileExtension = fileURL.pathExtension
    let outputURL = outputDirectory.appending(path: baseName)

    guard !fileExtension.isEmpty else {
        return outputURL
    }

    return outputURL.appendingPathExtension(fileExtension)
}

enum EditorDirectoryAccessError: LocalizedError {
    case revoked(URL)

    var errorDescription: String? {
        switch self {
        case .revoked(let url):
            LuxelLocalization.format(
                "quickExport.error.outputDirectoryAccessRevoked",
                defaultValue: "Luxel no longer has permission to save to %@. Choose the recordings folder again.",
                url.lastPathComponent)
        }
    }
}
