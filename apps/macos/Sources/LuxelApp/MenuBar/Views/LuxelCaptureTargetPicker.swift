import SwiftUI

struct LuxelCaptureTargetPicker: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Target")
                    .font(.caption.weight(.semibold))
                    .frame(width: 48, alignment: .leading)

                if !model.captureTargets.isEmpty {
                    Picker("Target", selection: $model.selectedCaptureTargetID) {
                        ForEach(model.captureTargets) { target in
                            CaptureTargetMenuLabel(target: target)
                                .tag(Optional(target.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.subheadline.weight(.semibold))
                    .controlSize(.small)
                    .onChange(of: model.selectedCaptureTargetID) {
                        model.syncCameraPreviewSnapArea()
                    }
                } else {
                    Label("No target", systemImage: "display")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(minHeight: 34)
            .luxelMenuSectionBackground(cornerRadius: 13)

            if let captureTargetStatusMessage = model.captureTargetStatusMessage {
                Text(captureTargetStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
