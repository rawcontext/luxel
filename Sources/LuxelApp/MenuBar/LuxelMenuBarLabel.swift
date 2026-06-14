import Foundation
import LuxelCore
import SwiftUI

struct LuxelMenuBarLabel: View {
    @Bindable var model: LuxelMenuModel
    @State private var now = Date()
    @State private var quickExportProgressPanelController = QuickExportProgressPanelController()

    var body: some View {
        let presentation = model.menuBarStatusPresentation(now: now)
        let title = menuBarTitle(for: presentation)

        HStack(spacing: 4) {
            MenuBarStatusIcon(
                systemImage: presentation.menuBarSystemImage,
                animates: presentation.animatesMenuBarSystemImage
            )

            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .lineLimit(1)
            }
        }
            .background {
                QuickExportProgressPanelHost(
                    model: model,
                    controller: quickExportProgressPanelController
                )
            }
            .accessibilityLabel(Text(presentation.accessibilityLabel))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    now = Date()
                }
            }
            .task {
                await model.keepCaptureTargetCacheWarm()
            }
    }

    private func menuBarTitle(for presentation: RecordingSessionPresentation) -> String? {
        switch presentation.menuBarTitle {
        case "", "Luxel":
            nil
        default:
            presentation.menuBarTitle
        }
    }

}

private struct MenuBarStatusIcon: View {
    let systemImage: String
    let animates: Bool
    @State private var recordingPulseIsDimmed = false

    var body: some View {
        Group {
            if showsRecordingGlyph {
                ZStack {
                    Image(systemName: "record.circle")
                        .opacity(animates ? 0.22 : 1)
                    Image(systemName: "record.circle.fill")
                        .opacity(animates ? (recordingPulseIsDimmed ? 0.55 : 1) : 0)
                        .scaleEffect(animates && recordingPulseIsDimmed ? 0.86 : 1)
                }
                .animation(.easeInOut(duration: 0.18), value: animates)
                .animation(
                    animates
                        ? .easeInOut(duration: 0.95).repeatForever(autoreverses: true)
                        : .easeInOut(duration: 0.18),
                    value: recordingPulseIsDimmed
                )
            } else {
                Image(systemName: systemImage)
            }
        }
            .font(.system(size: 14, weight: .regular))
            .imageScale(.medium)
            .frame(width: 18, height: 18)
            .task(id: animates) {
                guard animates else {
                    recordingPulseIsDimmed = false
                    return
                }

                recordingPulseIsDimmed = false
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else {
                    return
                }

                recordingPulseIsDimmed = true
            }
    }

    private var showsRecordingGlyph: Bool {
        systemImage == "record.circle" || systemImage == "record.circle.fill"
    }
}
