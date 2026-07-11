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
}
