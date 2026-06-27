import AppKit
import CoreImage
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
    private let backdropCornerRadius: CGFloat = 22

    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(4)
            .background {
                LuxelMenuPanelBackdrop(cornerRadius: backdropCornerRadius)
                    .clipShape(RoundedRectangle(cornerRadius: backdropCornerRadius, style: .continuous))
            }
            .background(Color.clear)
    }
}

private struct LuxelMenuPanelBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSGlassEffectView) {
        view.wantsLayer = true
        view.style = .clear
        view.tintColor = nil
        view.cornerRadius = cornerRadius
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.backgroundFilters = [Self.blurFilter()]
    }

    private static func blurFilter() -> CIFilter {
        let filter = CIFilter(name: "CIGaussianBlur") ?? CIFilter()
        filter.setValue(18.0, forKey: kCIInputRadiusKey)
        return filter
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
