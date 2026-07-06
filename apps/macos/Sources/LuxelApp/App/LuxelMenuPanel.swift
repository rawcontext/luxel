import AppKit
import SwiftUI

final class LuxelMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

struct LuxelMenuPanelChrome<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(4)
            .background(Color.clear)
    }
}

final class LuxelMenuHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = LuxelMenuHostingView(rootView: rootView)
    }
}

private final class LuxelMenuHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

final class LuxelMenuPanelContentView: NSView {
    override var isOpaque: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
