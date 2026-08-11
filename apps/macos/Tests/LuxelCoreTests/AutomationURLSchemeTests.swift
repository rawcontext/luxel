import Foundation
import LuxelCore
import Testing

extension AutomationCommandTests {
    @Test("URL builder and parser support a registered developer scheme")
    func urlBuilderAndParserSupportRegisteredDeveloperScheme() throws {
        let invocation = AutomationInvocation(command: .stop)
        let url = AutomationInvocationURLBuilder.url(for: invocation, scheme: "luxel-dev")

        #expect(url.absoluteString == "luxel-dev://stop")
        #expect(
            try AutomationCommandParser.parse(url, expectedScheme: "luxel-dev") == invocation
        )
        #expect(
            AutomationURLScheme.registered(in: [
                "CFBundleURLTypes": [["CFBundleURLSchemes": ["luxel-dev"]]]
            ]) == "luxel-dev"
        )
        #expect(CurrentProcessExecutable.url != nil)
        #expect(AutomationURLScheme.registered(containing: CurrentProcessExecutable.url) == "luxel")

        let appURL = FileManager.default.temporaryDirectory.appending(
            path: "LuxelAutomationScheme-\(UUID().uuidString).app",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: appURL) }
        let executableURL = appURL.appending(path: "Contents/MacOS/luxel-cli")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let infoPlist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleExecutable": "luxel-cli",
                "CFBundleIdentifier": "com.rawcontext.luxel.test",
                "CFBundlePackageType": "APPL",
                "CFBundleURLTypes": [["CFBundleURLSchemes": ["luxel-dev"]]]
            ],
            format: .xml,
            options: 0
        )
        try infoPlist.write(to: appURL.appending(path: "Contents/Info.plist"))
        try Data().write(to: executableURL)

        #expect(AutomationURLScheme.registered(containing: executableURL) == "luxel-dev")
    }
}
