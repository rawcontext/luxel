import AVFoundation
import Foundation

public struct AVFoundationMediaMetadataReader: MediaMetadataReader, MediaProbe, Sendable {
    public init() {}

    public func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw AVFoundationMediaMetadataReaderError.invalidDuration
        }

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw AVFoundationMediaMetadataReaderError.missingVideoTrack
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let width = Int(abs(naturalSize.width).rounded())
        let height = Int(abs(naturalSize.height).rounded())
        guard width > 0, height > 0 else {
            throw AVFoundationMediaMetadataReaderError.invalidNaturalSize
        }

        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let roundedFrameRate = Int(nominalFrameRate.rounded())
        guard roundedFrameRate > 0 else {
            throw AVFoundationMediaMetadataReaderError.invalidFrameRate
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        return try SourceMedia(
            fileURL: fileURL,
            duration: durationSeconds,
            pixelSize: PixelSize(width: width, height: height),
            nominalFrameRate: FrameRate(roundedFrameRate),
            hasAudio: !audioTracks.isEmpty
        )
    }

    public func inspectRecording(at fileURL: URL) async -> MediaProbeResult {
        do {
            _ = try await readSourceMedia(at: fileURL)
            return .playable
        } catch {
            return .corrupt(reason: String(describing: error))
        }
    }
}

public enum AVFoundationMediaMetadataReaderError: Error, Equatable {
    case invalidDuration
    case missingVideoTrack
    case invalidNaturalSize
    case invalidFrameRate
}
