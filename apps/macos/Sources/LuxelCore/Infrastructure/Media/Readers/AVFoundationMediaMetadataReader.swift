import AVFoundation
import CoreMedia
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
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
            throw AVFoundationMediaMetadataReaderError.missingMediaTracks
        }

        guard let videoTrack = videoTracks.first else {
            let audioTrackKinds = try await resolvedAudioTrackKinds(
                for: audioTracks,
                unmarkedFallback: .microphone
            )
            return try SourceMedia.audioOnly(
                fileURL: fileURL,
                duration: durationSeconds,
                audioTracks: audioTrackKinds
            )
        }

        let audioTrackKinds = try await resolvedAudioTrackKinds(
            for: audioTracks,
            unmarkedFallback: .system
        )

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

        let hasAlpha = try await hasAlphaChannel(in: videoTrack)

        return try SourceMedia(
            fileURL: fileURL,
            duration: durationSeconds,
            pixelSize: PixelSize(width: width, height: height),
            nominalFrameRate: FrameRate(roundedFrameRate),
            hasAudio: !audioTracks.isEmpty,
            hasAlpha: hasAlpha,
            audioTracks: audioTrackKinds
        )
    }

    public func inspectRecording(at fileURL: URL) async -> MediaProbeResult {
        do {
            let asset = AVURLAsset(url: fileURL)
            _ = try await validDuration(for: asset)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            guard !videoTracks.isEmpty || !audioTracks.isEmpty else {
                throw AVFoundationMediaMetadataReaderError.missingMediaTracks
            }

            if !videoTracks.isEmpty {
                _ = try await readSourceMedia(at: fileURL)
            }

            return .playable
        } catch {
            return .corrupt(reason: String(describing: error))
        }
    }

    private func validDuration(for asset: AVURLAsset) async throws -> TimeInterval {
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw AVFoundationMediaMetadataReaderError.invalidDuration
        }

        return durationSeconds
    }

    private func hasAlphaChannel(in videoTrack: AVAssetTrack) async throws -> Bool {
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)

        return formatDescriptions.contains { description in
            Self.mediaSubTypeSupportsAlpha(CMFormatDescriptionGetMediaSubType(description))
        }
    }

    static func mediaSubTypeSupportsAlpha(_ mediaSubType: CMVideoCodecType) -> Bool {
        switch mediaSubType {
        case kCMVideoCodecType_HEVCWithAlpha,
            kCMVideoCodecType_AppleProRes4444,
            kCMVideoCodecType_AppleProRes4444XQ:
            true
        default:
            false
        }
    }

    private func resolvedAudioTrackKinds(
        for audioTracks: [AVAssetTrack],
        unmarkedFallback: AudioTrackKind
    ) async throws
        -> [AudioTrackKind]
    {
        guard !audioTracks.isEmpty else {
            return []
        }

        let detectedKinds = try await AVFoundationAudioTrackMetadata.trackKinds(for: audioTracks)
        let markedKinds = detectedKinds.compactMap { $0 }
        guard !markedKinds.isEmpty else {
            return [unmarkedFallback]
        }

        return AudioTrackKind.allCases.filter { markedKinds.contains($0) }
    }
}

public enum AVFoundationMediaMetadataReaderError: LocalizedError, Equatable {
    case invalidDuration
    case missingVideoTrack
    case missingMediaTracks
    case invalidNaturalSize
    case invalidFrameRate

    public var errorDescription: String? {
        switch self {
        case .invalidDuration:
            "The recording duration could not be read."
        case .missingVideoTrack:
            "No video track was found in the recording."
        case .missingMediaTracks:
            "No playable audio or video tracks were found."
        case .invalidNaturalSize:
            "The recording video size could not be read."
        case .invalidFrameRate:
            "The recording frame rate could not be read."
        }
    }
}
