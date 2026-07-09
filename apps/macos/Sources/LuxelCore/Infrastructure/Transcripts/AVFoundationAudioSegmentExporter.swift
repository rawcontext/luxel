import AVFoundation
import CoreMedia
import Foundation

/// Shared AVFoundation helpers for isolating audio tracks and exporting short
/// audio segments to standalone M4A files (temporary diarization inputs and
/// known-speaker example clips).
public struct AVFoundationAudioSegmentExporter: Sendable {
    public enum ExportError: Error, Equatable, Sendable {
        case missingAudioTrack
        case exportFailed
    }

    private let temporaryDirectory: URL

    public init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.temporaryDirectory = temporaryDirectory
    }

    /// Exports one audio track of `audioURL` to a temporary M4A file.
    /// The caller owns the returned file and must delete it when done.
    public func isolatedTrackURL(from audioURL: URL, audioTrackIndex: Int) async throws -> URL {
        let outputURL =
            temporaryDirectory
            .appending(path: "LuxelAudioTrack-\(UUID().uuidString).m4a")
        return try await export(
            from: audioURL,
            audioTrackIndex: audioTrackIndex,
            timeRange: nil,
            to: outputURL
        )
    }

    /// Exports a time range of `audioURL` to `outputURL` as M4A.
    @discardableResult
    public func exportSegment(
        from audioURL: URL,
        start: TimeInterval,
        duration: TimeInterval,
        audioTrackIndex: Int? = nil,
        to outputURL: URL
    ) async throws -> URL {
        try await export(
            from: audioURL,
            audioTrackIndex: audioTrackIndex ?? 0,
            timeRange: CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            ),
            to: outputURL
        )
    }

    private func export(
        from audioURL: URL,
        audioTrackIndex: Int,
        timeRange: CMTimeRange?,
        to outputURL: URL
    ) async throws -> URL {
        let asset = AVURLAsset(url: audioURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.indices.contains(audioTrackIndex) else {
            throw ExportError.missingAudioTrack
        }

        let composition = AVMutableComposition()
        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ExportError.exportFailed
        }

        let duration = try await asset.load(.duration)
        let sourceRange =
            timeRange?.intersection(CMTimeRange(start: .zero, duration: duration))
            ?? CMTimeRange(start: .zero, duration: duration)
        try compositionTrack.insertTimeRange(
            sourceRange,
            of: audioTracks[audioTrackIndex],
            at: .zero
        )

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard
            let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetAppleM4A
            ),
            exportSession.supportedFileTypes.contains(.m4a)
        else {
            throw ExportError.exportFailed
        }

        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            return outputURL
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }
}
