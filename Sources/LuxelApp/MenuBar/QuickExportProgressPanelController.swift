import AppKit
import SwiftUI

@MainActor
final class QuickExportProgressPanelController {
    private var panel: NSPanel?
    private let panelSize = NSSize(width: 286, height: 78)

    func update(
        progress: QuickExportProgressPresentation?,
        onCancel: @escaping @MainActor () -> Void
    ) {
        guard let progress else {
            close()
            return
        }

        let panel = panel ?? makePanel()
        panel.setFrame(frame(for: panel.screen ?? NSScreen.main), display: false)
        panel.contentView = NSHostingView(
            rootView: QuickExportProgressPill(
                presentation: progress,
                onCancel: onCancel
            )
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = QuickExportProgressPanel(
            contentRect: frame(for: NSScreen.main),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    private func frame(for screen: NSScreen?) -> NSRect {
        let visibleFrame = (screen ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: visibleFrame.maxX - panelSize.width - 14,
            y: visibleFrame.maxY - panelSize.height - 8
        )
        return NSRect(origin: origin, size: panelSize)
    }
}

private final class QuickExportProgressPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

private struct QuickExportProgressPill: View {
    let presentation: QuickExportProgressPresentation
    let onCancel: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(presentation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 0)

                    Text(presentation.progressText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: presentation.snapshot.progress)
                    .progressViewStyle(.linear)
            }

            if presentation.canCancel {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.quaternary, in: Circle())
                .help("Cancel export")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 286, height: 78)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

struct QuickExportProgressPanelHost: View {
    let model: LuxelMenuModel
    let controller: QuickExportProgressPanelController

    var body: some View {
        let progress = model.quickExportProgress

        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                updatePanel(progress)
            }
            .onChange(of: progress) { _, newProgress in
                updatePanel(newProgress)
            }
            .onDisappear {
                controller.close()
            }
    }

    private func updatePanel(_ progress: QuickExportProgressPresentation?) {
        controller.update(progress: progress) {
            model.cancelQuickExport()
        }
    }
}
