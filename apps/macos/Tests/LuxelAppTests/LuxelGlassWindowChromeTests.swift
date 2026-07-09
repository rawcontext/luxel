import AppKit
import LuxelPresentation
import Testing

@MainActor
struct LuxelGlassWindowChromeTests {
    @Test("glass window chrome restores standard window controls")
    func restoresStandardWindowControls() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor

        LuxelGlassWindowChrome.configure(window)

        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .visible)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for button in buttons {
            #expect(window.standardWindowButton(button)?.isHidden == false)
        }

        let originalButtons = buttons.compactMap(window.standardWindowButton)
        LuxelGlassWindowChrome.configure(window)
        let reconfiguredButtons = buttons.compactMap(window.standardWindowButton)

        let pairedButtons = zip(originalButtons, reconfiguredButtons)
        let keptButtonInstances = pairedButtons.allSatisfy { originalButton, reconfiguredButton in
            originalButton === reconfiguredButton
        }
        #expect(keptButtonInstances)
    }
}
