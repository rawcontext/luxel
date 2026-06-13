import Foundation
import LuxelCore
import Testing

@Suite("Recording request")
struct RecordingRequestTests {
    @Test("audio modes expose capture intent")
    func audioModesExposeCaptureIntent() {
        #expect(!RecordingAudioMode.none.capturesSystemAudio)
        #expect(!RecordingAudioMode.none.capturesMicrophone)
        #expect(RecordingAudioMode.none.microphoneDeviceID == nil)

        #expect(RecordingAudioMode.system.capturesSystemAudio)
        #expect(!RecordingAudioMode.system.capturesMicrophone)
        #expect(RecordingAudioMode.system.microphoneDeviceID == nil)

        let microphone = RecordingAudioMode.microphone(deviceID: "mic-1")
        #expect(!microphone.capturesSystemAudio)
        #expect(microphone.capturesMicrophone)
        #expect(microphone.microphoneDeviceID == "mic-1")

        let combined = RecordingAudioMode.systemAndMicrophone(deviceID: "mic-2")
        #expect(combined.capturesSystemAudio)
        #expect(combined.capturesMicrophone)
        #expect(combined.microphoneDeviceID == "mic-2")
    }

    @Test("recording request derives persisted options")
    func recordingRequestDerivesPersistedOptions() throws {
        let displayID = DisplayID(37)
        let rect = try CaptureRect(x: 10, y: 20, width: 640, height: 480)
        let request = try RecordingRequest(
            target: .area(displayID: displayID, rect: rect),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(60),
            showCursor: false,
            highlightClicks: true,
            audio: .systemAndMicrophone(deviceID: "mic-1"),
            videoCodec: .hevc
        )

        #expect(request.recordingOptions.frameRate == 60)
        #expect(request.recordingOptions.captureRect == rect)
        #expect(request.recordingOptions.showCursor == false)
        #expect(request.recordingOptions.highlightClicks)
        #expect(request.recordingOptions.displayID == displayID)
        #expect(request.recordingOptions.audio == .systemAndMicrophone(deviceID: "mic-1"))
        #expect(request.recordingOptions.videoCodec == .hevc)
    }
}
