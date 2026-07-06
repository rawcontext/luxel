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

final class LuxelMenuPanelContentView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
