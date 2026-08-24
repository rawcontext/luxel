import Foundation
import Testing

@testable import LuxelCore

@Suite("App notifications")
struct UserNotificationsNotifierTests {
    @Test("export completion content carries actionable file paths")
    func exportCompletionContent() {
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/first.mp4"),
            URL(fileURLWithPath: "/tmp/second.gif")
        ]

        let content = UserNotificationsNotifier.exportCompletedContent(
            fileURLs: fileURLs,
            sourceName: "Luxel"
        )

        #expect(content.categoryIdentifier == ExportCompletionNotificationIdentifiers.category)
        #expect(content.title.isEmpty == false)
        #expect(content.body.contains("2"))
        #expect(content.sound != nil)
        #expect(
            content.userInfo[ExportCompletionNotificationIdentifiers.filePathsUserInfoKey]
                as? [String] == fileURLs.map(\.path)
        )
    }
}
