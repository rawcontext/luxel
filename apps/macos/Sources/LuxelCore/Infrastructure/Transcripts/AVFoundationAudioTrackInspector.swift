import AVFoundation
import Foundation

public struct AVFoundationAudioTrackInspector: AudioTrackInspector {
    public init() {}

    public func audioTrackCount(in audioURL: URL) async throws -> Int {
        try await audioTrackLayout(in: audioURL).count
    }

    public func audioTrackLayout(in audioURL: URL) async throws -> AudioTrackLayout {
        let asset = AVURLAsset(url: audioURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let trackKinds = try await AVFoundationAudioTrackMetadata.trackKinds(for: audioTracks)
        return AudioTrackLayout(trackKinds: trackKinds)
    }
}
