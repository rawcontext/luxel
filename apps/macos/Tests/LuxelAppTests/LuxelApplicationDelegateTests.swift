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
        "URL open requests forward media files to the editor handler",
        arguments: ["m4a", "mp4"]
    )
    func urlOpenRequestsForwardMediaFiles(pathExtension: String) {
        let delegate = LuxelApplicationDelegate()
        let mediaURL = URL(fileURLWithPath: "/tmp/recording.\(pathExtension)")
        var receivedURLs: [[URL]] = []
        delegate.openFiles = { urls, _ in
            receivedURLs.append(urls)
        }

        delegate.application(
            NSApplication.shared,
            open: [mediaURL, URL(string: "luxel://record")!]
        )

        #expect(receivedURLs == [[mediaURL]])
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
        #expect(source.contains("title: \"Settings\""))
        #expect(source.contains("title: \"Quit Luxel\""))
        #expect(source.contains("showStatusItemQuickActionsMenu()"))
    }
}
