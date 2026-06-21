import LuxelCore
import Testing

@Suite("Capture permission presentation")
struct CapturePermissionPresentationTests {
    @Test("screen denied and mic authorized keeps audio-only available")
    func screenDeniedAndMicAuthorizedKeepsAudioOnlyAvailable() {
        let state = makeState(
            screen: .denied,
            microphone: .authorized,
            camera: .denied,
            recordsMicrophone: true
        )

        #expect(!state.screenRecordingAvailable)
        #expect(!state.areaRecordingAvailable)
        #expect(state.audioOnlyRecordingAvailable)
        #expect(state.microphoneTrackAvailable)
    }

    @Test("screen authorized and mic denied keeps screen recording available")
    func screenAuthorizedAndMicDeniedKeepsScreenRecordingAvailable() {
        let state = makeState(
            screen: .authorized,
            microphone: .denied,
            camera: .authorized,
            recordsMicrophone: true
        )

        #expect(state.screenRecordingAvailable)
        #expect(state.areaRecordingAvailable)
        #expect(!state.microphoneTrackAvailable)
        #expect(state.microphone.phase == .needsGrant)
        #expect(state.microphone.systemImage == "mic.slash")
    }

    @Test("screen authorized and system audio off keeps silent screen recording available")
    func screenAuthorizedAndSystemAudioOffKeepsSilentScreenRecordingAvailable() {
        let state = makeState(
            screen: .authorized,
            microphone: .authorized,
            camera: .authorized,
            recordsSystemAudio: false,
            recordsMicrophone: true
        )

        #expect(state.screenRecordingAvailable)
        #expect(!state.systemAudioTrackAvailable)
        #expect(state.systemAudio.phase == .offByUser)
        #expect(state.systemAudio.systemImage == "speaker.slash.fill")
    }

    @Test("screen authorized and system audio on keeps audio-only available without microphone")
    func screenAuthorizedAndSystemAudioOnKeepsAudioOnlyAvailableWithoutMicrophone() {
        let state = makeState(
            screen: .authorized,
            microphone: .denied,
            camera: .authorized,
            recordsSystemAudio: true,
            recordsMicrophone: false
        )

        #expect(state.audioOnlyRecordingAvailable)
        #expect(state.systemAudioTrackAvailable)
        #expect(!state.microphoneTrackAvailable)
        #expect(state.systemAudio.phase == .ready)
    }

    @Test("screen authorized and camera denied keeps recording available")
    func screenAuthorizedAndCameraDeniedKeepsRecordingAvailable() {
        let state = makeState(
            screen: .authorized,
            microphone: .authorized,
            camera: .denied,
            recordsMicrophone: true,
            hasCameraSelection: true
        )

        #expect(state.screenRecordingAvailable)
        #expect(state.microphoneTrackAvailable)
        #expect(!state.cameraOverlayAvailable)
        #expect(state.camera.phase == .needsGrant)
        #expect(state.camera.systemImage == "video.slash")
    }

    @Test("camera permission missing takes precedence over no camera selection")
    func cameraPermissionMissingTakesPrecedenceOverNoCameraSelection() {
        let state = makeState(
            screen: .authorized,
            microphone: .authorized,
            camera: .notDetermined,
            recordsMicrophone: true,
            hasCameraSelection: false
        )

        #expect(state.screenRecordingAvailable)
        #expect(!state.cameraOverlayAvailable)
        #expect(state.camera.phase == .needsGrant)
        #expect(state.camera.actionTitle == "Enable Camera")
        #expect(state.camera.statusTitle == "Required")
    }

    @Test("all denied blocks screen actions and leaves off source controls")
    func allDeniedBlocksScreenActionsAndLeavesOffSourceControls() {
        let state = makeState(
            screen: .denied,
            microphone: .denied,
            camera: .denied,
            recordsSystemAudio: true,
            recordsMicrophone: true,
            hasCameraSelection: true
        )

        #expect(state.screen.phase == .needsGrant)
        #expect(state.systemAudio.phase == .needsGrant)
        #expect(state.screen.message.contains("click +"))
        #expect(state.systemAudio.message.contains("click +"))
        #expect(state.microphone.phase == .needsGrant)
        #expect(state.camera.phase == .needsGrant)
        #expect(!state.screenRecordingAvailable)
        #expect(!state.systemAudioTrackAvailable)
        #expect(!state.microphoneTrackAvailable)
        #expect(!state.cameraOverlayAvailable)
    }

    private func makeState(
        screen: PermissionStatus = .authorized,
        microphone: PermissionStatus = .authorized,
        camera: PermissionStatus = .authorized,
        recordsSystemAudio: Bool = true,
        recordsMicrophone: Bool = false,
        hasCameraSelection: Bool = false
    ) -> CaptureCapabilityState {
        CaptureCapabilityState(
            screenRecordingStatus: screen,
            microphoneStatus: microphone,
            cameraStatus: camera,
            recordsSystemAudio: recordsSystemAudio,
            recordsMicrophone: recordsMicrophone,
            hasCameraSelection: hasCameraSelection,
            hasSelectedCaptureTarget: true,
            hasLastCaptureMemory: true
        )
    }
}
