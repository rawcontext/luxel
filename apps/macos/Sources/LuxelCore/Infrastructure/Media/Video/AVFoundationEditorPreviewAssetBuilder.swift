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
                guard
                    let track = composition.addMutableTrack(
                        withMediaType: mediaType,
                        preferredTrackID: kCMPersistentTrackID_Invalid
                    )
                else {
                    throw AVFoundationPreviewBuilderError.cannotCreateTrack
                }
                didCreateTrack = true

                try track.insert(sourceSegments, from: sourceTrack)

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
