import Foundation
import LuxelCore
import Testing

@Suite("App bundle configuration")
struct AppBundleConfigurationTests {
    @Test("Info plist declares Luxel app metadata and protected resource usage")
    func infoPlistDeclaresAppMetadataAndProtectedResourceUsage() throws {
        let plist = try readPlist("Configuration/Luxel/Info.plist")

        #expect(plist["CFBundleName"] as? String == "Luxel")
        #expect(plist["CFBundleDisplayName"] as? String == "Luxel")
        #expect(plist["CFBundleExecutable"] as? String == "Luxel")
        #expect(plist["CFBundleIdentifier"] as? String == "com.rawcontext.luxel")
        #expect(plist["CFBundleShortVersionString"] as? String == "1.1.10")
        #expect(plist["CFBundleVersion"] as? String == "1")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSMinimumSystemVersion"] as? String == "26.0")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(
            plist["NSHumanReadableCopyright"] as? String
                == "Copyright © 2026 Context. All rights reserved.")
        let urlTypes = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
        let luxelURLType = try #require(urlTypes.first)
        #expect(luxelURLType["CFBundleURLName"] as? String == "com.rawcontext.luxel.url")
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
        #expect(microphonePurpose.contains("speech detection"))
        #expect(microphonePurpose.contains("saved only after you start recording"))

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
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.server"] == nil)
    }

    @Test("signed app declares local-only privacy practices")
    func signedAppDeclaresLocalOnlyPrivacyPractices() throws {
        let manifest = try readPlist("Configuration/Luxel/PrivacyInfo.xcprivacy")
        let tracking = try #require(manifest["NSPrivacyTracking"] as? Bool)
        let collectedData = try #require(manifest["NSPrivacyCollectedDataTypes"] as? [Any])
        let accessedAPIs = try #require(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let reasons = Dictionary(uniqueKeysWithValues: try accessedAPIs.map { entry in
            let category = try #require(entry["NSPrivacyAccessedAPIType"] as? String)
            let values = try #require(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
            return (category, values)
        })

        #expect(!tracking)
        #expect(collectedData.isEmpty)
        #expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["DDA9.1"])
        #expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"])
        #expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"])

        let support = try scriptSource("luxel-app-bundle-support.sh")
        #expect(support.contains("Contents/Resources/PrivacyInfo.xcprivacy"))
        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName)
            #expect(script.contains("PRIVACY_MANIFEST="))
        }
    }

}

extension AppBundleConfigurationTests {
    @Test("build script bundles third-party license ledger as app resource")
    func buildScriptBundlesThirdPartyLicenseLedgerAsAppResource() throws {
        let script = try scriptSource("build-luxel-app.sh")
        let support = try scriptSource("luxel-app-bundle-support.sh")

        #expect(script.contains("THIRD_PARTY_LICENSES"))
        #expect(script.contains("source \"${PACKAGE_ROOT}/Scripts/luxel-app-bundle-support.sh\""))
        #expect(support.contains("Contents/Resources"))
        #expect(support.contains("ThirdPartyLicenses.md"))
    }

    @Test("signed app scripts bundle Studio Voice model resources")
    func signedAppScriptsBundleStudioVoiceResources() throws {
        let support = try scriptSource("luxel-app-bundle-support.sh")
        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName)
            #expect(script.contains("source \"${PACKAGE_ROOT}/Scripts/luxel-app-bundle-support.sh\""))
        }
        #expect(support.contains("STUDIO_VOICE_MODEL_DIR"))
        #expect(support.contains("Contents/Resources/Models"))
        #expect(support.contains("ThirdPartyLicenses.md"))
    }

    @Test("signed app scripts require and audit bundled MODNet resources")
    func signedAppScriptsRequireAndAuditBundledMODNetResources() throws {
        let root = try packageRootURL()
        try runModelAudit(
            root: root,
            script: "audit-modnet-model.sh",
            modelDirectory: "modnet"
        )

        let support = try scriptSource("luxel-app-bundle-support.sh")
        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName)
            #expect(script.contains("MODNET_MODEL_DIR"))
            #expect(script.contains("audit-modnet-model.sh"))
            #expect(!script.contains("if [[ -d \"${MODNET_MODEL_DIR}"))
        }
        #expect(support.contains("cp -R \"${MODNET_MODEL_DIR}\""))
        #expect(!support.contains("if [[ -d \"${MODNET_MODEL_DIR}"))
    }

    @Test("signed app scripts require and audit bundled voice activity detection resources")
    func signedAppScriptsRequireAndAuditBundledVoiceActivityDetectionResources() throws {
        let root = try packageRootURL()
        try runModelAudit(
            root: root,
            script: "audit-voice-activity-detection-model.sh",
            modelDirectory: "voice-activity-detection"
        )

        let support = try scriptSource("luxel-app-bundle-support.sh")
        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName)
            #expect(script.contains("VAD_MODEL_DIR"))
            #expect(script.contains("audit-voice-activity-detection-model.sh"))
            #expect(!script.contains("if [[ -d \"${VAD_MODEL_DIR}"))
        }
        #expect(support.contains("cp -R \"${VAD_MODEL_DIR}\""))
        #expect(support.contains("\"${VAD_MODEL_AUDITOR}\" \"${APP_PATH}\""))
        #expect(!support.contains("if [[ -d \"${VAD_MODEL_DIR}"))
    }

    @Test("local build script uses a development app identity by default")
    func localBuildScriptUsesDevelopmentAppIdentityByDefault() throws {
        let scriptURL = try packageRootURL().appending(path: "Scripts/build-luxel-app.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(
            script.contains("APPLE_TEAM_IDENTIFIER=\"${APPLE_TEAM_IDENTIFIER:-U65DCW9TAK}\""))
        #expect(script.contains("find_signing_identity_for_team 'Apple Development:'"))
        #expect(
            script.contains("APP_BUNDLE_IDENTIFIER=\"${APP_BUNDLE_IDENTIFIER:-com.rawcontext.luxel.dev}\""))
        #expect(script.contains("APP_DISPLAY_NAME=\"${APP_DISPLAY_NAME:-Luxel Dev}\""))
        #expect(script.contains("APP_URL_SCHEME=\"${APP_URL_SCHEME:-luxel-dev}\""))
        #expect(
            script.contains("APP_PATH=\"${APP_PATH:-${PACKAGE_ROOT}/dist/${APP_DISPLAY_NAME}.app}\""))
        #expect(script.contains("Set :CFBundleIdentifier ${APP_BUNDLE_IDENTIFIER}"))
        #expect(script.contains("Set :CFBundleDisplayName ${APP_DISPLAY_NAME}"))
        #expect(script.contains("Set :CFBundleName ${APP_DISPLAY_NAME}"))
        #expect(script.contains("Set :CFBundleURLTypes:0:CFBundleURLName ${APP_BUNDLE_IDENTIFIER}.url"))
        #expect(script.contains("Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 ${APP_URL_SCHEME}"))
        #expect(script.contains("set_luxel_localized_bundle_display_name \"${APP_DISPLAY_NAME}\""))
    }

    @Test("local build rewrites only assembled localized app names")
    func localBuildRewritesOnlyAssembledLocalizedAppNames() throws {
        let root = try packageRootURL()
        let macAppStoreScript = try scriptSource("build-luxel-mas-pkg.sh")
        #expect(!macAppStoreScript.contains("set_luxel_localized_bundle_display_name"))

        let localizations = root.appending(path: "Configuration/Luxel/Localizations")
        let temporaryRoot = FileManager.default.temporaryDirectory.appending(
            component: "luxel-localized-display-name-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let appPath = temporaryRoot.appending(
            component: "Luxel Dev.app",
            directoryHint: .isDirectory
        )
        let resources = appPath.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        for locale in LuxelLocalization.supportedLocales {
            let source = localizations.appending(
                path: "\(locale).lproj",
                directoryHint: .isDirectory
            )
            let destination = resources.appending(
                path: "\(locale).lproj",
                directoryHint: .isDirectory
            )
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let supportScript = root.appending(path: "Scripts/luxel-app-bundle-support.sh")
        try rewriteLocalizedDisplayName(in: appPath, using: supportScript)

        for locale in LuxelLocalization.supportedLocales {
            let source = localizations
                .appending(path: "\(locale).lproj")
                .appending(path: "InfoPlist.strings")
            let assembled = resources
                .appending(path: "\(locale).lproj")
                .appending(path: "InfoPlist.strings")
            let sourcePlist = try readPlist(at: source)
            let assembledPlist = try readPlist(at: assembled)

            #expect(sourcePlist["CFBundleDisplayName"] as? String == "Luxel")
            #expect(sourcePlist["CFBundleName"] as? String == "Luxel")
            #expect(assembledPlist["CFBundleDisplayName"] as? String == "Luxel Dev")
            #expect(assembledPlist["CFBundleName"] as? String == "Luxel Dev")
        }
    }

    @Test("signing scripts select identities from the Raw Context team")
    func signingScriptsSelectIdentitiesFromRawContextTeam() throws {
        let support = try scriptSource("signing-identity-support.sh")
        #expect(support.contains("security find-certificate"))
        #expect(support.contains("certificate_team_identifier"))

        for scriptName in [
            "build-luxel-app.sh",
            "benchmark-transcription.sh",
            "build-luxel-mas-pkg.sh"
        ] {
            let script = try scriptSource(scriptName)
            #expect(
                script.contains(
                    "APPLE_TEAM_IDENTIFIER=\"${APPLE_TEAM_IDENTIFIER:-U65DCW9TAK}\""))
            #expect(script.contains("signing-identity-support.sh"))
            #expect(script.contains("find_signing_identity_for_team"))
        }
    }

    @Test("build script does not bundle an external command line executable")
    func buildScriptDoesNotBundleCommandLineExecutable() throws {
        let script = try scriptSource("build-luxel-app.sh")
        let support = try scriptSource("luxel-app-bundle-support.sh")

        #expect(!script.contains("--product luxel-cli"))
        #expect(!script.contains("Contents/MacOS/luxel-cli"))
        #expect(!support.contains("Contents/MacOS/luxel-cli"))
    }

    @Test("Mac App Store package script bundles SwiftPM resources")
    func macAppStorePackageScriptBundlesSwiftPMResources() throws {
        let script = try scriptSource("build-luxel-mas-pkg.sh")
        let support = try scriptSource("luxel-app-bundle-support.sh")

        #expect(support.contains("find \"${BIN_DIR}\" -maxdepth 1 -name '*.bundle'"))
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

    @Test("app launch never terminates over purchase verification")
    func appLaunchNeverTerminatesOverPurchaseVerification() throws {
        let root = try packageRootURL()
        let appSource = try String(
            contentsOf: root.appending(path: "Sources/LuxelApp/App/LuxelApp.swift"),
            encoding: .utf8
        )
        #expect(appSource.contains("@main\nstruct LuxelApp: App"))
        #expect(!appSource.contains("purchaseGateService"))
        #expect(!appSource.contains("NSApp.terminate(nil)"))
    }

    private func readPlist(_ relativePath: String) throws -> [String: Any] {
        let url = try packageRootURL().appending(path: relativePath)
        return try readPlist(at: url)
    }

    private func readPlist(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    private func rewriteLocalizedDisplayName(in appPath: URL, using supportScript: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "APP_PATH=\"$1\"; source \"$2\"; set_luxel_localized_bundle_display_name \"Luxel Dev\"",
            "luxel-localized-display-name",
            appPath.path,
            supportScript.path
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func runModelAudit(root: URL, script: String, modelDirectory: String) throws {
        let process = Process()
        process.executableURL = root.appending(path: "Scripts/\(script)")
        process.arguments = [root.appending(path: "Vendor/Models/\(modelDirectory)").path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func scriptSource(_ scriptName: String) throws -> String {
        try String(
            contentsOf: packageRootURL().appending(path: "Scripts/\(scriptName)"),
            encoding: .utf8
        )
    }

    private func packageRootURL() throws -> URL {
        try sharedPackageRootURL()
    }
}
