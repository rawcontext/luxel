import AppKit
import Foundation
import Testing

@testable import LuxelApp

@MainActor
struct LuxelApplicationDelegateTests {
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
