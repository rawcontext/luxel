import AppKit
import LuxelPresentation
import SwiftUI
import Testing

@MainActor
@Suite(.serialized)
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

    @Test("scene glass chrome preserves functional system window controls")
    func sceneGlassChromePreservesSystemWindowControls() async throws {
        let application = NSApplication.shared
        let originalActivationPolicy = application.activationPolicy()
        let title = "Luxel Scene Chrome Test \(UUID().uuidString)"
        var openedWindow: NSWindow?
        defer {
            openedWindow?.close()
            _ = application.setActivationPolicy(originalActivationPolicy)
        }

        _ = application.setActivationPolicy(.regular)
        let scene = NSHostingSceneRepresentation {
            Settings {
                Color.clear
                    .frame(minWidth: 840, minHeight: 660)
                    .navigationTitle(title)
                    .background {
                        LuxelGlassWindowBackground()
                            .overlay(LuxelGlassWindowTransparencyConfigurator())
                    }
                    .luxelGlassSceneWindowChrome()
            }
            .defaultSize(width: 920, height: 760)
            .windowResizability(.contentMinSize)
            .windowBackgroundDragBehavior(.enabled)
        }
        application.addSceneRepresentation(scene)
        application.finishLaunching()
        scene.environment.openSettings()

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            openedWindow = application.windows.first { $0.title == title }
            if openedWindow != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let window = try #require(openedWindow)
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titleVisibility == .hidden)
        #expect(window.titlebarAppearsTransparent)
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)

        try expectFunctionalSystemWindowControls(in: window)
    }

    private func expectFunctionalSystemWindowControls(in window: NSWindow) throws {
        let frameView = try #require(window.contentView?.superview)
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttonTypes {
            let button = try #require(window.standardWindowButton(buttonType))
            #expect(button.window === window)
            #expect(button.isEnabled)
            #expect(!button.isHiddenOrHasHiddenAncestor)
            #expect(button.alphaValue > 0)
            #expect(!button.bounds.isEmpty)

            let screenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            #expect(window.frame.intersects(screenFrame))

            let hitTestPoint = frameView.convert(
                NSPoint(x: button.bounds.midX, y: button.bounds.midY),
                from: button
            )
            #expect(frameView.hitTest(hitTestPoint) === button)
        }
    }
}
