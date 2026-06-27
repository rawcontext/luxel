import LuxelCore
import SwiftUI

struct LuxelCaptureTargetPicker: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Target")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 50, alignment: .leading)

                if !model.captureTargets.isEmpty {
                    Menu {
                        ForEach(model.captureTargets) { target in
                            Button {
                                model.selectedCaptureTargetID = target.id
                                model.syncCameraPreviewSnapArea()
                            } label: {
                                CaptureTargetMenuLabel(target: target)
                            }
                        }
                    } label: {
                        CaptureTargetPickerLabel(target: model.selectedCaptureTarget)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                } else {
                    Label("No target", systemImage: "display")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: 38)
            .luxelMenuSectionBackground(cornerRadius: 19)

            if let captureTargetStatusMessage = model.captureTargetStatusMessage {
                Text(captureTargetStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct CaptureTargetPickerLabel: View {
    let target: CaptureTargetOption?

    var body: some View {
        HStack(spacing: 8) {
            if let target {
                CaptureTargetMenuLabel(target: target)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
            } else {
                Label("No target", systemImage: "display")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 28)
        .luxelMenuControlBackground(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
