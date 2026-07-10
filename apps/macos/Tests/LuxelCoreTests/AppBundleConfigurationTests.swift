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
        #expect(entitlements["com.apple.security.network.client"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.server"] == nil)
    }

    @Test("Mac App Store CLI entitlements sandbox terminal-facing command")
    func macAppStoreCLIEntitlementsSandboxTerminalFacingCommand() throws {
        let entitlements = try readPlist("Configuration/Luxel/LuxelCLI.MacAppStore.entitlements")

        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.server"] as? Bool == true)
        #expect(entitlements["com.apple.security.network.client"] == nil)
        #expect(entitlements["com.apple.security.inherit"] == nil)
    }

    @Test("downloadable precision model artifacts stay out of the source bundle and vendor tree")
    func downloadablePrecisionModelArtifactsStayOutOfDistributionInputs() throws {
        let root = try packageRootURL()
        for relativePath in ["Sources", "Vendor"] {
            let directory = root.appending(path: relativePath, directoryHint: .isDirectory)
            guard
                let enumerator = FileManager.default.enumerator(
                    at: directory, includingPropertiesForKeys: nil)
            else { continue }
            for case let url as URL in enumerator {
                let path = url.path
                #expect(!path.contains("parakeet-tdt-0.6b-v3-coreml"))
                #expect(!path.hasSuffix("Encoder.mlmodelc"))
                #expect(!path.hasSuffix("JointDecisionv3.mlmodelc"))
                #expect(!path.contains("aed02740059203c4a87495924f685de3722ae9ce"))
            }
        }
    }

    @Test("signed app and Mac App Store builders audit Precision model exclusion")
    func distributionBuildersAuditPrecisionModelExclusion() throws {
        let root = try packageRootURL()
        let auditPath = "Scripts/audit-precision-model-bundle.sh"
        let audit = try String(
            contentsOf: root.appending(path: auditPath),
            encoding: .utf8
        )
        let developerBuilder = try String(
            contentsOf: root.appending(path: "Scripts/build-luxel-app.sh"),
            encoding: .utf8
        )
        let storeBuilder = try String(
            contentsOf: root.appending(path: "Scripts/build-luxel-mas-pkg.sh"),
            encoding: .utf8
        )

        #expect(audit.contains("Encoder\\.mlmodelc"))
        #expect(audit.contains("JointDecisionv3\\.mlmodelc"))
        #expect(audit.contains("aed02740059203c4a87495924f685de3722ae9ce"))
        #expect(developerBuilder.contains("audit-precision-model-bundle.sh"))
        #expect(storeBuilder.contains("\"${PRECISION_MODEL_AUDITOR}\" \"${APP_PATH}\""))
        #expect(storeBuilder.contains("\"${PRECISION_MODEL_AUDITOR}\" \"${PKG_PATH}\""))
    }

    @Test("Precision model bundle auditor rejects forbidden payload paths")
    func precisionModelBundleAuditorRejectsForbiddenPaths() throws {
        let root = try packageRootURL()
        let fixture = FileManager.default.temporaryDirectory.appending(
            path: "LuxelBundleAudit-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: fixture) }
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        let auditor = root.appending(path: "Scripts/audit-precision-model-bundle.sh")

        let clean = Process()
        clean.executableURL = auditor
        clean.arguments = [fixture.path]
        try clean.run()
        clean.waitUntilExit()
        #expect(clean.terminationStatus == 0)

        try FileManager.default.createDirectory(
            at: fixture.appending(path: "Encoder.mlmodelc"),
            withIntermediateDirectories: true
        )
        let forbidden = Process()
        forbidden.executableURL = auditor
        forbidden.arguments = [fixture.path]
        try forbidden.run()
        forbidden.waitUntilExit()
        #expect(forbidden.terminationStatus != 0)
    }

    @Test("runtime and CLI have no implicit Precision model download path")
    func runtimeAndCLIHaveNoImplicitPrecisionDownloadPath() throws {
        let root = try packageRootURL()
        let precisionRuntime = try [
            "Sources/LuxelCore/Infrastructure/Transcripts/PrecisionTranscription.swift",
            "Sources/LuxelCore/Infrastructure/Transcripts/ParakeetPrecisionModelValidator.swift"
        ].map {
            try String(contentsOf: root.appending(path: $0), encoding: .utf8)
        }.joined(separator: "\n")
        let composition = try String(
            contentsOf: root.appending(
                path: "Sources/LuxelApp/App/LuxelCompositionRoot+Models.swift"
            ),
            encoding: .utf8
        )
        let cli = try String(
            contentsOf: root.appending(path: "Sources/LuxelCLI/LuxelCLIHeadless.swift"),
            encoding: .utf8
        )

        #expect(!precisionRuntime.contains("downloadAndLoad"))
        #expect(!precisionRuntime.contains("resolve/main"))
        #expect(precisionRuntime.contains("ModelHub.offlineMode = true"))
        #expect(composition.contains("FluidAudioOfflinePolicy.enable()"))
        #expect(!cli.contains("AsrModels"))
        #expect(!cli.contains("HuggingFaceModelArtifactDownloadClient"))
        #expect(!cli.contains("PrecisionTranscriptionEngine"))
    }

}

extension AppBundleConfigurationTests {
    @Test("model catalog generator verifies the production catalog offline")
    func modelCatalogGeneratorVerifiesProductionCatalogOffline() throws {
        let root = try packageRootURL()
        let process = Process()
        process.currentDirectoryURL = root
        process.executableURL = root.appending(path: "Scripts/generate-model-catalog.swift")
        process.arguments = ["verify"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
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

    @Test("signed app scripts require and audit bundled MODNet resources")
    func signedAppScriptsRequireAndAuditBundledMODNetResources() throws {
        let root = try packageRootURL()
        let auditor = root.appending(path: "Scripts/audit-modnet-model.sh")
        let auditProcess = Process()
        auditProcess.executableURL = auditor
        auditProcess.arguments = [root.appending(path: "Vendor/Models/modnet").path]
        try auditProcess.run()
        auditProcess.waitUntilExit()
        #expect(auditProcess.terminationStatus == 0)

        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try String(
                contentsOf: root.appending(path: "Scripts/\(scriptName)"),
                encoding: .utf8
            )
            #expect(script.contains("MODNET_MODEL_DIR"))
            #expect(script.contains("audit-modnet-model.sh"))
            #expect(script.contains("cp -R \"${MODNET_MODEL_DIR}\""))
            #expect(!script.contains("if [[ -d \"${MODNET_MODEL_DIR}"))
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
