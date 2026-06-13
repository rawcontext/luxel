import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation audio-only recorder")
struct AVFoundationAudioOnlyRecorderTests {
    @Test("recorder rejects system audio until ScreenCaptureKit audio-only path exists")
    func recorderRejectsSystemAudioUntilScreenCaptureKitPathExists() async throws {
        let recorder = AVFoundationAudioOnlyRecorder()
        let request = try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
            audio: .system
        )

        await #expect(throws: AVFoundationAudioOnlyRecorderError.unsupportedAudioSource) {
            try await recorder.startRecording(request)
        }
    }
}
