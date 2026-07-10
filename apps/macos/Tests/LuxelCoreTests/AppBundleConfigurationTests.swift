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
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0.25")
        #expect(plist["CFBundleVersion"] as? String == "1")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(
            plist["NSHumanReadableCopyright"] as? String
                == "Copyright © 2026 Context. All rights reserved.")
        let urlTypes = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let luxelURLType = try #require(urlTypes.first)
        #expect(luxelURLType["CFBundleURLName"] as? String == "media.luxel.app.url")
        #expect(luxelURLType["CFBundleURLSchemes"] as? [String] == ["luxel"])

        let documentTypes = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(documentTypes.count == 2)
        #expect(
            documentTypes.map { $0["CFBundleTypeName"] as? String }
                == ["Luxel Video", "Luxel Audio"])
        #expect(documentTypes.allSatisfy { $0["CFBundleTypeRole"] as? String == "Editor" })
        #expect(documentTypes.allSatisfy { $0["LSHandlerRank"] as? String == "Alternate" })
        #expect(
            documentTypes.compactMap { $0["LSItemContentTypes"] as? [String] }
                == [["public.movie"], ["public.audio"]])

        let microphonePurpose = try #require(plist["NSMicrophoneUsageDescription"] as? String)
        #expect(microphonePurpose.contains("microphone"))
        #expect(microphonePurpose.contains("screen recording"))

        let cameraPurpose = try #require(plist["NSCameraUsageDescription"] as? String)
        #expect(cameraPurpose.contains("camera"))
        #expect(cameraPurpose.contains("camera-track recording"))

        let screenCapturePurpose = try #require(plist["NSScreenCaptureUsageDescription"] as? String)
        #expect(screenCapturePurpose.contains("screen"))
        #expect(screenCapturePurpose.contains("recording"))
    }

    @Test("Developer ID entitlements allow capture devices without sandboxing")
    func developerIDEntitlementsAllowCaptureDevicesWithoutSandboxing() throws {
        let entitlements = try readPlist("Configuration/Luxel/Luxel.DeveloperID.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] == nil)
        #expect(entitlements["com.apple.security.device.audio-input"] as? Bool == true)
        #expect(entitlements["com.apple.security.device.camera"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.user-selected.read-write"] == nil)
        #expect(entitlements["com.apple.security.get-task-allow"] == nil)
    }

    @Test("Mac App Store entitlements allow sandboxed local capture access")
    func macAppStoreEntitlementsAllowSandboxedLocalCaptureAccess() throws {
        let entitlements = try readPlist("Configuration/Luxel/Luxel.MacAppStore.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.assets.movies.read-write"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool == true)
        #expect(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] == nil)
    }

    @Test("Mac App Store CLI entitlements sandbox terminal-facing command")
    func macAppStoreCLIEntitlementsSandboxTerminalFacingCommand() throws {
        let entitlements = try readPlist("Configuration/Luxel/LuxelCLI.MacAppStore.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.server"] as? Bool == true)
        #expect(entitlements["com.apple.security.inherit"] == nil)
    }

    @Test("build script bundles third-party license ledger as app resource")
    func buildScriptBundlesThirdPartyLicenseLedgerAsAppResource() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("THIRD_PARTY_LICENSES"))
        #expect(script.contains("Contents/Resources"))
        #expect(script.contains("ThirdPartyLicenses.md"))
    }

    @Test("signed app scripts bundle Studio Voice model resources")
    func signedAppScriptsBundleStudioVoiceResources() throws {
        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let scriptURL = try packageRootURL().appending(path: "Scripts/\(scriptName)")
            let script = try String(contentsOf: scriptURL, encoding: .utf8)

            #expect(script.contains("Vendor/Models/studio-voice"))
            #expect(script.contains("Contents/Resources/Models"))
            #expect(script.contains("ThirdPartyLicenses.md"))
        }
    }

    @Test("local build script uses a development app identity by default")
    func localBuildScriptUsesDevelopmentAppIdentityByDefault() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(
            script.contains("APP_BUNDLE_IDENTIFIER=\"${APP_BUNDLE_IDENTIFIER:-media.luxel.app.dev}\""))
        #expect(script.contains("APP_DISPLAY_NAME=\"${APP_DISPLAY_NAME:-Luxel Dev}\""))
        #expect(script.contains("APP_URL_SCHEME=\"${APP_URL_SCHEME:-luxel-dev}\""))
        #expect(
            script.contains("APP_PATH=\"${APP_PATH:-${PACKAGE_ROOT}/dist/${APP_DISPLAY_NAME}.app}\""))
        #expect(script.contains("Set :CFBundleIdentifier ${APP_BUNDLE_IDENTIFIER}"))
        #expect(script.contains("Set :CFBundleDisplayName ${APP_DISPLAY_NAME}"))
        #expect(script.contains("Set :CFBundleName ${APP_DISPLAY_NAME}"))
        #expect(script.contains("Set :CFBundleURLTypes:0:CFBundleURLName ${APP_BUNDLE_IDENTIFIER}.url"))
        #expect(script.contains("Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 ${APP_URL_SCHEME}"))
    }

    @Test("build script bundles and signs CLI executable")
    func buildScriptBundlesAndSignsCLIExecutable() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("swift build --configuration \"${CONFIGURATION}\" --product luxel-cli"))
        #expect(script.contains("Contents/MacOS/luxel-cli"))
        #expect(script.contains("xcrun strip -x \"${APP_PATH}/Contents/MacOS/luxel-cli\""))
        #expect(script.contains("\"${APP_PATH}/Contents/MacOS/luxel-cli\""))
        #expect(!script.contains("Contents/Resources/install-cli"))
    }

    @Test("Mac App Store package script bundles SwiftPM resources")
    func macAppStorePackageScriptBundlesSwiftPMResources() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-mas-pkg.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("find \"${BIN_DIR}\" -maxdepth 1 -name '*.bundle'"))
        #expect(script.contains("Contents/Resources/Luxel_LuxelCore.bundle"))
        #expect(script.contains("CFBundleIdentifier"))
        #expect(script.contains("LuxelCore resource bundle was not copied"))
    }

    @Test("build script requires team signing")
    func buildScriptRequiresTeamSigning() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("Ad-hoc signing is not allowed"))
        #expect(script.contains("TeamIdentifier"))
        #expect(!script.contains("SIGN_IDENTITY:--"))
        #expect(!script.contains("--timestamp=none"))
    }

    @Test("distribution split check covers default and Mac App Store builds")
    func distributionSplitCheckCoversDefaultAndMacAppStoreBuilds() throws {
        let scriptURL = try packageRootURL().appending(
            path: "Scripts/check-app-distribution-build-split.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(script.contains("swift test --filter AppDistributionTests"))
        #expect(script.contains("-DLUXEL_MAC_APP_STORE"))
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
