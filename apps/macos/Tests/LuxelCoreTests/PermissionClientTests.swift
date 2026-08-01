import LuxelCore
import Testing

@Suite("Permission model")
struct PermissionClientTests {
    @Test("permissions and statuses are framework-free value models")
    func permissionsAndStatusesAreValueModels() {
        #expect(SystemPermission.screenRecording != .microphone)
        #expect(SystemPermission.camera != .microphone)
        #expect(SystemPermission.inputMonitoring != .screenRecording)
        #expect(PermissionStatus.notDetermined != .authorized)
        #expect(PermissionStatus.denied != .restricted)
    }

    @Test("input monitoring guidance explains consent and recovery")
    func inputMonitoringGuidanceExplainsConsentAndRecovery() {
        let consent = PermissionGuidanceService().guidance(
            for: .inputMonitoring,
            status: .notDetermined
        )
        let denied = PermissionGuidanceService().guidance(
            for: .inputMonitoring,
            status: .denied
        )

        #expect(consent.actionTitle == "Open System Settings")
        #expect(consent.action == .openSettings)
        #expect(consent.message.contains("typed characters"))
        #expect(consent.message.contains("locally"))
        #expect(consent.message.contains("pause"))
        #expect(denied.action == .openSettings)
        #expect(denied.message.contains("Input Monitoring"))
        #expect(denied.message.contains("relaunch"))
    }

    @Test(
        "screen recording guidance opens screen and system audio settings without native request prompt"
    )
    func screenRecordingGuidanceOpensScreenAndSystemAudioSettingsWithoutNativeRequestPrompt() {
        let notDetermined = PermissionGuidanceService().guidance(
            for: .screenRecording,
            status: .notDetermined
        )
        let guidance = PermissionGuidanceService().guidance(
            for: .screenRecording,
            status: .denied
        )

        #expect(notDetermined.actionTitle == "Open System Settings")
        #expect(notDetermined.action == .openSettings)
        #expect(notDetermined.message.contains("Screen & System Audio Recording"))
        #expect(guidance.title == "Screen capture is off")
        #expect(guidance.actionTitle == "Open System Settings")
        #expect(guidance.action == .openSettings)
        #expect(guidance.message.contains("Screen & System Audio Recording"))
        #expect(guidance.message.contains("click +"))
    }

    @Test("microphone guidance opens settings without native request prompt")
    func microphoneGuidanceOpensSettingsWithoutNativeRequestPrompt() {
        expectSettingsGuidance(for: .microphone)
    }

    @Test("camera guidance opens settings without native request prompt")
    func cameraGuidanceOpensSettingsWithoutNativeRequestPrompt() {
        expectSettingsGuidance(for: .camera)
    }

    private func expectSettingsGuidance(for permission: SystemPermission) {
        let notDetermined = PermissionGuidanceService().guidance(
            for: permission,
            status: .notDetermined
        )
        let denied = PermissionGuidanceService().guidance(
            for: permission,
            status: .denied
        )

        #expect(notDetermined.actionTitle == "Open System Settings")
        #expect(notDetermined.action == .openSettings)
        #expect(denied.actionTitle == "Open System Settings")
        #expect(denied.action == .openSettings)
    }

    @Test("system audio guidance uses screen and system audio recovery")
    func systemAudioGuidanceUsesScreenAndSystemAudioRecovery() {
        let deniedState = CaptureCapabilityState(
            screenRecordingStatus: .denied,
            microphoneStatus: .authorized,
            cameraStatus: .authorized,
            recordsSystemAudio: true,
            recordsMicrophone: true,
            hasCameraSelection: false
        )
        let notDeterminedState = CaptureCapabilityState(
            screenRecordingStatus: .notDetermined,
            microphoneStatus: .authorized,
            cameraStatus: .authorized,
            recordsSystemAudio: true,
            recordsMicrophone: true,
            hasCameraSelection: false
        )
        let guidance = PermissionGuidanceService().guidance(
            for: .systemAudio,
            presentation: deniedState.systemAudio,
            status: .denied
        )

        #expect(guidance.title == "System sound is off")
        #expect(guidance.actionTitle == "Open System Settings")
        #expect(guidance.action == .openSettings)
        #expect(guidance.message.contains("Screen & System Audio Recording"))
        #expect(guidance.message.contains("click +"))

        let notDeterminedGuidance = PermissionGuidanceService().guidance(
            for: .systemAudio,
            presentation: notDeterminedState.systemAudio,
            status: .notDetermined
        )

        #expect(notDeterminedGuidance.actionTitle == "Open System Settings")
        #expect(notDeterminedGuidance.action == .openSettings)
        #expect(notDeterminedGuidance.message.contains("Screen & System Audio Recording"))
        #expect(notDeterminedGuidance.message.contains("click +"))
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
