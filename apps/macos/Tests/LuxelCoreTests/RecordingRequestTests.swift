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
        let schedule = try RecordingSchedule(countdown: 3, maxRecordedDuration: 60)
        let camera = CameraRecordingOptions(
            deviceID: "camera-1",
            isEnabled: true,
            recordsSeparateTrack: true,
            previewStyle: CameraPreviewStyle(shape: .roundedRect, size: .large, isMirrored: false)
        )
        let request = try RecordingRequest(
            target: .area(displayID: displayID, rect: rect),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(60),
            showCursor: false,
            highlightClicks: true,
            captureKeystrokes: true,
            camera: camera,
            audio: .systemAndMicrophone(deviceID: "mic-1"),
            videoCodec: .hevc,
            schedule: schedule
        )

        #expect(request.camera == camera)
        #expect(request.recordingOptions.frameRate == 60)
        #expect(request.recordingOptions.captureRect == rect)
        #expect(request.recordingOptions.showCursor == false)
        #expect(request.recordingOptions.highlightClicks)
        #expect(request.recordingOptions.captureKeystrokes)
        #expect(request.recordingOptions.camera == camera)
        #expect(request.recordingOptions.displayID == displayID)
        #expect(request.recordingOptions.audio == .systemAndMicrophone(deviceID: "mic-1"))
        #expect(request.recordingOptions.videoCodec == .hevc)
        #expect(request.recordingOptions.schedule == schedule)
        #expect(request.recordingOptions.timelapse == nil)
    }

    @Test("time-lapse request disables audio and persists options")
    func timelapseRequestDisablesAudioAndPersistsOptions() throws {
        let timelapse = try TimelapseOptions(speedFactor: 30, playbackFrameRate: FrameRate(30))
        let request = try RecordingRequest(
            target: .display(DisplayID(10)),
            outputFileURL: URL(fileURLWithPath: "/tmp/timelapse.mp4"),
            pixelSize: PixelSize(width: 1920, height: 1080),
            frameRate: FrameRate(30),
            audio: .microphone(deviceID: "mic-1"),
            timelapse: timelapse
        )

        #expect(request.audio == .none)
        #expect(request.recordingOptions.audio == .none)
        #expect(request.timelapse == timelapse)
        #expect(request.recordingOptions.timelapse == timelapse)
    }
}
