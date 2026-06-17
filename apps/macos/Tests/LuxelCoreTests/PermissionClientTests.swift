import LuxelCore
import Testing

@Suite("Permission model")
struct PermissionClientTests {
    @Test("permissions and statuses are framework-free value models")
    func permissionsAndStatusesAreValueModels() {
        #expect(SystemPermission.screenRecording != .microphone)
        #expect(SystemPermission.camera != .microphone)
        #expect(PermissionStatus.notDetermined != .authorized)
        #expect(PermissionStatus.denied != .restricted)
    }

    @Test("screen recording guidance opens screen and system audio settings after denial")
    func screenRecordingGuidanceOpensScreenAndSystemAudioSettingsAfterDenial() {
        let guidance = PermissionGuidanceService().guidance(
            for: .screenRecording,
            status: .denied
        )

        #expect(guidance.title == "Screen capture is off")
        #expect(guidance.actionTitle == "Open System Settings")
        #expect(guidance.action == .openSettings)
        #expect(guidance.message.contains("Screen & System Audio Recording"))
    }

    @Test("microphone guidance requests before denial and opens settings after denial")
    func microphoneGuidanceRequestsBeforeDenialAndOpensSettingsAfterDenial() {
        let notDetermined = PermissionGuidanceService().guidance(
            for: .microphone,
            status: .notDetermined
        )
        let denied = PermissionGuidanceService().guidance(
            for: .microphone,
            status: .denied
        )

        #expect(notDetermined.actionTitle == "Continue")
        #expect(notDetermined.action == .request)
        #expect(denied.actionTitle == "Open System Settings")
        #expect(denied.action == .openSettings)
    }

    @Test("camera guidance requests before denial and opens settings after denial")
    func cameraGuidanceRequestsBeforeDenialAndOpensSettingsAfterDenial() {
        let notDetermined = PermissionGuidanceService().guidance(
            for: .camera,
            status: .notDetermined
        )
        let denied = PermissionGuidanceService().guidance(
            for: .camera,
            status: .denied
        )

        #expect(notDetermined.actionTitle == "Continue")
        #expect(notDetermined.action == .request)
        #expect(denied.actionTitle == "Open System Settings")
        #expect(denied.action == .openSettings)
    }

    @Test("system audio guidance uses screen and system audio recovery")
    func systemAudioGuidanceUsesScreenAndSystemAudioRecovery() {
        let state = CaptureCapabilityState(
            screenRecordingStatus: .denied,
            microphoneStatus: .authorized,
            cameraStatus: .authorized,
            recordsSystemAudio: true,
            recordsMicrophone: true,
            hasCameraSelection: false
        )
        let guidance = PermissionGuidanceService().guidance(
            for: .systemAudio,
            presentation: state.systemAudio,
            status: .denied
        )

        #expect(guidance.title == "System sound is off")
        #expect(guidance.actionTitle == "Open System Settings")
        #expect(guidance.action == .openSettings)
        #expect(guidance.message.contains("Screen & System Audio Recording"))
    }

    @Test("authorized system audio off state enables only system audio source")
    func authorizedSystemAudioOffStateEnablesOnlySystemAudioSource() {
        let state = CaptureCapabilityState(
            screenRecordingStatus: .authorized,
            microphoneStatus: .authorized,
            cameraStatus: .authorized,
            recordsSystemAudio: false,
            recordsMicrophone: true,
            hasCameraSelection: false
        )
        let guidance = PermissionGuidanceService().guidance(
            for: .systemAudio,
            presentation: state.systemAudio,
            status: .authorized
        )

        #expect(guidance.title == "System sound is off")
        #expect(guidance.actionTitle == "Enable System Sound")
        #expect(guidance.action == .enableSource)
    }

    @Test("authorized microphone off state enables only microphone source")
    func authorizedMicrophoneOffStateEnablesOnlyMicrophoneSource() {
        let state = CaptureCapabilityState(
            screenRecordingStatus: .authorized,
            microphoneStatus: .authorized,
            cameraStatus: .authorized,
            recordsSystemAudio: true,
            recordsMicrophone: false,
            hasCameraSelection: false
        )
        let guidance = PermissionGuidanceService().guidance(
            for: .microphone,
            presentation: state.microphone,
            status: .authorized
        )

        #expect(guidance.title == "Microphone is off")
        #expect(guidance.actionTitle == "Enable Mic")
        #expect(guidance.action == .enableSource)
    }
}
