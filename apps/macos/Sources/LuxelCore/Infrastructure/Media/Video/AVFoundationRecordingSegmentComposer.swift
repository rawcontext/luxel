import AVFoundation
import CoreMedia
import Foundation

public struct AVFoundationRecordingSegmentComposer {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func compose(_ segmentFileURLs: [URL], to outputFileURL: URL) async throws {
        guard !segmentFileURLs.isEmpty else {
            throw RecordingSegmentComposerError.missingSegments
        }

        if segmentFileURLs.count == 1 {
            try replaceOutput(at: outputFileURL, with: segmentFileURLs[0])
            return
        }

        let composition = AVMutableComposition()
        var insertionTime = CMTime.zero

        for segmentFileURL in segmentFileURLs {
            let asset = AVURLAsset(url: segmentFileURL)
            let duration = try await asset.load(.duration)

            guard duration > .zero else {
                continue
            }

            try await composition.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: asset,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, duration)
        }

        guard insertionTime > .zero else {
            throw RecordingSegmentComposerError.emptyComposition
        }

        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            )
        else {
            throw RecordingSegmentComposerError.unsupportedPreset(AVAssetExportPresetHighestQuality)
        }

        guard exportSession.supportedFileTypes.contains(.mp4) else {
            throw RecordingSegmentComposerError.unsupportedOutputFileType(AVFileType.mp4.rawValue)
        }

        let replacementFileURL =
            outputFileURL
            .deletingLastPathComponent()
            .appending(
                path:
                    ".\(outputFileURL.deletingPathExtension().lastPathComponent)-merged-\(UUID().uuidString)"
            )
            .appendingPathExtension(
                outputFileURL.pathExtension.isEmpty ? "mp4" : outputFileURL.pathExtension)

        try? fileManager.removeItem(at: replacementFileURL)

        do {
            try await exportSession.export(to: replacementFileURL, as: .mp4)
            try replaceOutput(at: outputFileURL, with: replacementFileURL)
        } catch {
            try? fileManager.removeItem(at: replacementFileURL)
            throw error
        }
    }

    private func replaceOutput(at outputFileURL: URL, with replacementFileURL: URL) throws {
        if outputFileURL == replacementFileURL {
            return
        }

        try? fileManager.removeItem(at: outputFileURL)
        try fileManager.moveItem(at: replacementFileURL, to: outputFileURL)
    }
}

public enum RecordingSegmentComposerError: Error, Equatable {
    case missingSegments
    case emptyComposition
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
}
