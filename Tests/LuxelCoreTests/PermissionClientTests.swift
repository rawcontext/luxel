import LuxelCore
import Testing

@Suite("Permission model")
struct PermissionClientTests {
    @Test("permissions and statuses are framework-free value models")
    func permissionsAndStatusesAreValueModels() {
        #expect(SystemPermission.screenRecording != .microphone)
        #expect(PermissionStatus.notDetermined != .authorized)
        #expect(PermissionStatus.denied != .restricted)
    }

    @Test("screen recording guidance requests access and mentions relaunch")
    func screenRecordingGuidanceRequestsAccessAndMentionsRelaunch() {
        let guidance = PermissionGuidanceService().guidance(
            for: .screenRecording,
            status: .denied
        )

        #expect(guidance.title == "Screen Recording Permission")
        #expect(guidance.actionTitle == "Continue")
        #expect(guidance.action == .request)
        #expect(guidance.message.contains("System Settings"))
        #expect(guidance.message.contains("quit and reopen Luxel"))
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
        #expect(denied.actionTitle == "Open Settings")
        #expect(denied.action == .openSettings)
    }
}
