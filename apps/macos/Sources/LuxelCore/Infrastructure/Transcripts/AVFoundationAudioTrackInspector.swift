import AVFoundation
import Foundation

public struct AVFoundationAudioTrackInspector: AudioTrackInspector {
    public init() {}

    public func audioTrackCount(in audioURL: URL) async throws -> Int {
        let asset = AVURLAsset(url: audioURL)
        return try await asset.loadTracks(withMediaType: .audio).count
    }
}
