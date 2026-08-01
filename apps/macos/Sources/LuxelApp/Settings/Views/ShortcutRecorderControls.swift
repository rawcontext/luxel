import AppKit
import LuxelCore
import LuxelPresentation
import SwiftUI

struct ShortcutKeybindingLabel: View {
    let rawValue: String

    var body: some View {
        if let shortcut = AppKeyboardShortcut(rawValue: rawValue) {
            Text(shortcut.compactDisplayName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.1), in: Capsule())
                .lineLimit(1)
        } else {
            Text("Unassigned")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    let onShortcut: (AppKeyboardShortcut) -> Void
    let onInvalidShortcut: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onShortcut = onShortcut
        view.onInvalidShortcut = onInvalidShortcut
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.onShortcut = onShortcut
        nsView.onInvalidShortcut = onInvalidShortcut
        nsView.onCancel = onCancel
        nsView.requestFocus()
    }
}

final class ShortcutRecorderNSView: NSView {
    var onShortcut: ((AppKeyboardShortcut) -> Void)?
    var onInvalidShortcut: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        NSColor.black.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = "Press shortcut" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let size = text.size(withAttributes: attributes)
        let rect = NSRect(
            x: 14,
            y: (bounds.height - size.height) / 2,
            width: bounds.width - 28,
            height: size.height
        )
        text.draw(in: rect, withAttributes: attributes)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestFocus()
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard handle(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handle(event)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return false
        }

        if event.keyCode == 53 {
            onCancel?()
            return true
        }

        guard let shortcut = event.luxelShortcut else {
            onInvalidShortcut?()
            return true
        }

        onShortcut?(shortcut)
        return true
    }
}

extension NSEvent {
    fileprivate var luxelShortcut: AppKeyboardShortcut? {
        guard let rawKey = charactersIgnoringModifiers?.lowercased(),
              rawKey.count == 1,
              let scalar = rawKey.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar)
        else {
            return nil
        }

        return try? AppKeyboardShortcut(key: rawKey, modifiers: appShortcutModifiers)
    }
}
