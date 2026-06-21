import Foundation
import Testing

@testable import LuxelCore

@Suite("Past recording models")
struct PastRecordingTests {
    @Test("video recording excludes audio-only recordings")
    func videoRecordingExcludesAudioOnlyRecordings() {
        #expect(videoRecording().isVideoRecording)
        #expect(!audioOnlyRecording().isVideoRecording)
    }

    private func videoRecording() -> PastRecording {
        PastRecording(
            fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            name: "Video",
            date: Date(timeIntervalSince1970: 0),
            options: RecordingOptions(frameRate: 60)
        )
    }

    private func audioOnlyRecording() -> PastRecording {
        PastRecording(
            fileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            name: "Audio",
            date: Date(timeIntervalSince1970: 0),
            options: RecordingOptions(frameRate: 0, isAudioOnly: true)
        )
    }

}
