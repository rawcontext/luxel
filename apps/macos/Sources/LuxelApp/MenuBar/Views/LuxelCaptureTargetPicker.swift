import LuxelCore
import SwiftUI

struct LuxelCaptureTargetPicker: View {
    @Bindable var model: LuxelMenuModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Source")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 50, alignment: .leading)

                if !model.captureTargets.isEmpty {
                    Menu {
                        captureTargetMenuSection(
                            "Displays",
                            targets: captureTargets(kind: .display)
                        )

                        captureTargetMenuSection(
                            "Apps & Windows",
                            targets: captureTargets(kind: .window)
                        )
                    } label: {
                        CaptureTargetPickerLabel(target: model.selectedCaptureTarget)
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                } else {
                    Label("No source", systemImage: "display")
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

    @ViewBuilder
    private func captureTargetMenuSection(
        _ title: String,
        targets: [CaptureTargetOption]
    ) -> some View {
        if !targets.isEmpty {
            Section(title) {
                ForEach(targets) { target in
                    Toggle(isOn: captureTargetSelection(target)) {
                        CaptureTargetMenuLabel(target: target)
                    }
                }
            }
        }
    }

    private func captureTargets(kind: CaptureTargetKind) -> [CaptureTargetOption] {
        model.captureTargets.filter { $0.kind == kind }
    }

    private func captureTargetSelection(_ target: CaptureTargetOption) -> Binding<Bool> {
        Binding {
            target.id == model.selectedCaptureTargetID
        } set: { isSelected in
            guard isSelected else {
                return
            }

            model.selectedCaptureTargetID = target.id
            model.syncCameraPreviewSnapArea()
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
                Label("No source", systemImage: "display")
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
