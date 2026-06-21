import SwiftUI

struct LuxelReplayBufferControls: View {
    let model: LuxelMenuModel

    var body: some View {
        let presentation = model.replayBufferMenuPresentation

        if presentation.isVisible {
            Divider()

            Button {
            } label: {
                Label(presentation.clipActionTitle, systemImage: "gobackward")
            }
            .disabled(!presentation.canClip)

            Button {
            } label: {
                Label(presentation.pauseActionTitle, systemImage: "pause.circle")
            }
            .disabled(!presentation.canPause)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(presentation.statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
