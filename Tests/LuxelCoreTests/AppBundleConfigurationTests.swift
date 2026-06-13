import Foundation
import Testing

@Suite("App bundle configuration")
struct AppBundleConfigurationTests {
    @Test("Info plist declares Luxel app metadata and protected resource usage")
    func infoPlistDeclaresAppMetadataAndProtectedResourceUsage() throws {
        let plist = try readPlist("Configuration/Luxel/Info.plist")

        #expect(plist["CFBundleName"] as? String == "Luxel")
        #expect(plist["CFBundleDisplayName"] as? String == "Luxel")
        #expect(plist["CFBundleExecutable"] as? String == "Luxel")
        #expect(plist["CFBundleIdentifier"] as? String == "media.luxel.app")
        #expect(plist["CFBundleShortVersionString"] as? String == "0.1.0")
        #expect(plist["CFBundleVersion"] as? String == "1")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(plist["LSUIElement"] as? Bool == true)

        let microphonePurpose = try #require(plist["NSMicrophoneUsageDescription"] as? String)
        #expect(microphonePurpose.contains("microphone"))
        #expect(microphonePurpose.contains("screen recording"))
    }

    @Test("Developer ID entitlements do not opt into sandbox-only permissions")
    func developerIDEntitlementsDoNotOptIntoSandboxOnlyPermissions() throws {
        let entitlements = try readPlist("Configuration/Luxel/Luxel.DeveloperID.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] == nil)
        #expect(entitlements["com.apple.security.device.audio-input"] == nil)
        #expect(entitlements["com.apple.security.files.user-selected.read-write"] == nil)
        #expect(entitlements["com.apple.security.get-task-allow"] == nil)
    }

    private func readPlist(_ relativePath: String) throws -> [String: Any] {
        let url = try packageRootURL().appending(path: relativePath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
