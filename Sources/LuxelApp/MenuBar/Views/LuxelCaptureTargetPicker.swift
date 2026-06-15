import SwiftUI

struct LuxelCaptureTargetPicker: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        if !model.captureTargets.isEmpty {
            Picker("Target", selection: $model.selectedCaptureTargetID) {
                ForEach(model.captureTargets) { target in
                    Label(target.menuTitle, systemImage: target.systemImage)
                        .tag(Optional(target.id))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: model.selectedCaptureTargetID) {
                model.syncCameraPreviewSnapArea()
            }
        }

        if let captureTargetStatusMessage = model.captureTargetStatusMessage {
            Text(captureTargetStatusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
