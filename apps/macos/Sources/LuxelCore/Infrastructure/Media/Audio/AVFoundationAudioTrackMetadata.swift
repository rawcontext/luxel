@preconcurrency import AVFoundation
import Foundation

enum AVFoundationAudioTrackMetadata {
    static func writerMetadata(for kind: AudioTrackKind) -> [AVMetadataItem] {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.extendedLanguageTag = "und"
        item.value = kind.assetTrackTitle as NSString
        return [item]
    }

    static func trackKinds(for tracks: [AVAssetTrack]) async throws -> [AudioTrackKind?] {
        var kinds: [AudioTrackKind?] = []
        kinds.reserveCapacity(tracks.count)

        for track in tracks {
            kinds.append(try await kind(for: track))
        }

        return kinds
    }

    static func kind(for track: AVAssetTrack) async throws -> AudioTrackKind? {
        let metadata = try await track.load(.metadata)
        let commonMetadata = try await track.load(.commonMetadata)
        if let kind = await kind(in: metadata) {
            return kind
        }

        return await kind(in: commonMetadata)
    }

    static func kind(in metadata: [AVMetadataItem]) async -> AudioTrackKind? {
        for item in metadata {
            guard let title = try? await item.load(.stringValue),
                  let kind = AudioTrackKind(assetTrackTitle: title)
            else {
                continue
            }

            return kind
        }

        return nil
    }
}
