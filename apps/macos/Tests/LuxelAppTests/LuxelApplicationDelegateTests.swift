import AppKit
import Foundation
import Testing

@testable import LuxelApp

@MainActor
struct LuxelApplicationDelegateTests {
    @Test("Tooltip configuration registers a prompt default delay without overriding preferences")
    func tooltipConfigurationRegistersDefaultWithoutOverridingPreferences() {
        let defaults = UserDefaults(suiteName: #function)!
        defer {
            defaults.removePersistentDomain(forName: #function)
        }

        LuxelTooltipConfiguration.registerDefaults(in: defaults)

        #expect(
            defaults.integer(forKey: LuxelTooltipConfiguration.initialDelayDefaultsKey)
                == LuxelTooltipConfiguration.initialDelayMilliseconds
        )

        defaults.set(750, forKey: LuxelTooltipConfiguration.initialDelayDefaultsKey)
        LuxelTooltipConfiguration.registerDefaults(in: defaults)

        #expect(
            defaults.integer(forKey: LuxelTooltipConfiguration.initialDelayDefaultsKey) == 750
        )
    }

    @Test(
        "URL open requests forward files and automation to their handlers",
        arguments: ["m4a", "mp4"]
    )
    func urlOpenRequestsForwardMediaFiles(pathExtension: String) {
        let delegate = LuxelApplicationDelegate()
        let mediaURL = URL(fileURLWithPath: "/tmp/recording.\(pathExtension)")
        let automationURL = URL(string: "luxel://record")!
        var receivedURLs: [[URL]] = []
        var receivedAutomationURLs: [[URL]] = []
        delegate.openFiles = { urls, _ in
            receivedURLs.append(urls)
        }
        delegate.openURLs = { urls in
            receivedAutomationURLs.append(urls)
        }

        delegate.application(
            NSApplication.shared,
            open: [mediaURL, automationURL]
        )

        #expect(receivedURLs == [[mediaURL]])
        #expect(receivedAutomationURLs == [[automationURL]])
    }

    @Test("URL Apple events forward automation without a SwiftUI window")
    func urlAppleEventsForwardAutomation() {
        let delegate = LuxelApplicationDelegate()
        let automationURL = URL(string: "luxel://preferences")!
        var receivedURLs: [[URL]] = []
        delegate.openURLs = { receivedURLs.append($0) }

        delegate.handleURLString(automationURL.absoluteString)

        #expect(receivedURLs == [[automationURL]])
    }

    @Test("URL Apple events wait until the app installs its handler")
    func urlAppleEventsWaitForHandler() {
        let delegate = LuxelApplicationDelegate()
        let automationURL = URL(string: "luxel://doctor")!
        var receivedURLs: [[URL]] = []

        delegate.handleURLString(automationURL.absoluteString)
        delegate.openURLs = { receivedURLs.append($0) }

        #expect(receivedURLs == [[automationURL]])
    }

    @Test("status item right click exposes the overflow quick actions")
    func statusItemRightClickQuickActions() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let controllerSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelApp/App/LuxelStatusItemController.swift"
            ),
            encoding: .utf8
        )
        let quickActionsSource = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelApp/App/LuxelStatusItemController+QuickActions.swift"
            ),
            encoding: .utf8
        )
        let source = controllerSource + quickActionsSource

        #expect(source.contains("[.leftMouseUp, .rightMouseUp]"))
        #expect(source.contains("NSApp.currentEvent?.type == .rightMouseUp"))
        #expect(source.contains("title: String(localized: \"Settings\")"))
        #expect(source.contains("title: String(localized: \"Quit Luxel\")"))
        #expect(source.contains("showStatusItemQuickActionsMenu()"))
    }
}
