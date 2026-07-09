import AVFoundation
import Foundation
import Testing

@testable import LuxelCore

@Suite("AVFoundation audio track metadata")
struct AVFoundationAudioTrackMetadataTests {
    @Test("metadata helper round trips Luxel track roles")
    func metadataHelperRoundTripsLuxelTrackRoles() async {
        #expect(
            await AVFoundationAudioTrackMetadata.kind(
                in: AVFoundationAudioTrackMetadata.writerMetadata(for: .microphone)
            ) == .microphone
        )
        #expect(
            await AVFoundationAudioTrackMetadata.kind(
                in: AVFoundationAudioTrackMetadata.writerMetadata(for: .system)
            ) == .system
        )
    }
}
