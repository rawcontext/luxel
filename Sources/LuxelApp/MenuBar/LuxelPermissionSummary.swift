import SwiftUI

struct LuxelPermissionSummary: View {
    let model: LuxelMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PermissionRow(
                title: "Screen Recording",
                status: model.screenRecordingStatus,
                actionTitle: model.permissionActionTitle(for: .screenRecording)
            ) {
                model.presentPermissionPrompt(for: .screenRecording)
            }

            PermissionRow(
                title: "Microphone",
                status: model.microphoneStatus,
                actionTitle: model.permissionActionTitle(for: .microphone)
            ) {
                model.presentPermissionPrompt(for: .microphone)
            }
        }
    }
}
