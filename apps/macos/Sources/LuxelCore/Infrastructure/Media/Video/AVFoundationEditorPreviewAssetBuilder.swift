import AVFoundation
import CoreMedia
import Foundation

public struct AVFoundationEditorPreviewAssetBuilder: Sendable {
    public init() {}

    public func makePreviewAsset(
        inputFileURL: URL,
        sourceSegments: [SourceMediaSegment]
    ) async throws -> AVComposition {
        let asset = AVURLAsset(url: inputFileURL)
        let composition = AVMutableComposition()
        var didCreateTrack = false

        for mediaType in [AVMediaType.video, .audio] {
            for sourceTrack in try await asset.loadTracks(withMediaType: mediaType) {
                guard let track = composition.addMutableTrack(
                    withMediaType: mediaType,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw AVFoundationPreviewBuilderError.cannotCreateTrack
                }
                didCreateTrack = true

                for segment in sourceSegments {
                    try track.insertTimeRange(
                        CMTimeRange(
                            start: CMTime(
                                seconds: segment.sourceRange.start,
                                preferredTimescale: 60_000
                            ),
                            duration: CMTime(
                                seconds: segment.sourceRange.duration,
                                preferredTimescale: 60_000
                            )
                        ),
                        of: sourceTrack,
                        at: CMTime(seconds: segment.outputStart, preferredTimescale: 60_000)
                    )
                }

                if mediaType == .video {
                    track.preferredTransform = try await sourceTrack.load(.preferredTransform)
                }
            }
        }

        guard didCreateTrack else {
            throw AVFoundationPreviewBuilderError.missingTracks
        }

        return composition
    }
}

public enum AVFoundationPreviewBuilderError: Error, Equatable {
    case cannotCreateTrack
    case missingTracks
}
