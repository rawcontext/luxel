import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class AppKitScreenshotThumbnailPresenter: ScreenshotThumbnailPresenter {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func present(_ item: ScreenshotThumbnailItem) {
        guard let image = NSImage(data: item.imageData.data) else {
            return
        }

        dismissTask?.cancel()
        panel?.close()

        let panelSize = NSSize(width: 220, height: 154)
        let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: screenFrame.maxX - panelSize.width - 24,
            y: screenFrame.minY + 24
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: panelSize),
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
        panel.contentView = NSHostingView(
            rootView: ScreenshotThumbnailView(
                item: item,
                image: image
            )
        )

        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                self?.panel?.close()
                self?.panel = nil
            }
        }
    }
}

private struct ScreenshotThumbnailView: View {
    let item: ScreenshotThumbnailItem
    let image: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScreenshotThumbnailDragView(item: item, image: image)
                .frame(width: 196, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(item.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 220, height: 154, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1)
        }
    }
}

private struct ScreenshotThumbnailDragView: NSViewRepresentable {
    let item: ScreenshotThumbnailItem
    let image: NSImage

    func makeNSView(context: Context) -> ScreenshotThumbnailDragImageView {
        let view = ScreenshotThumbnailDragImageView()
        view.update(item: item, image: image)
        return view
    }

    func updateNSView(_ nsView: ScreenshotThumbnailDragImageView, context: Context) {
        nsView.update(item: item, image: image)
    }
}

private final class ScreenshotThumbnailDragImageView: NSImageView, NSDraggingSource {
    private var item: ScreenshotThumbnailItem?
    private var mouseDownEvent: NSEvent?
    private var activePromise: AppKitScreenshotFilePromise?

    init() {
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(item: ScreenshotThumbnailItem, image: NSImage) {
        self.item = item
        self.image = image
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let item, let image, let mouseDownEvent else {
            return
        }

        let promise = AppKitScreenshotFilePromise(
            imageData: item.imageData,
            fileName: item.fileName,
            sourceFileURL: item.fileURL
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: promise.makeProvider())
        draggingItem.setDraggingFrame(bounds, contents: image)
        activePromise = promise
        beginDraggingSession(with: [draggingItem], event: mouseDownEvent, source: self)
        self.mouseDownEvent = nil
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        activePromise = nil
    }
}
