import Foundation
import Testing

@Suite("Bundled model configuration")
struct BundledModelConfigurationTests {
    @Test("signed app scripts require and audit bundled speaker diarization resources")
    func signedAppScriptsRequireAndAuditBundledSpeakerDiarizationResources() throws {
        let root = try sharedPackageRootURL()
        try runAudit(
            root: root,
            script: "audit-speaker-diarization-model.sh",
            modelDirectory: "speaker-diarization"
        )

        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName, root: root)
            #expect(script.contains("audit-speaker-diarization-model.sh"))
            #expect(
                script.contains(
                    "bash \"${SPEAKER_DIARIZATION_MODEL_AUDITOR}\" \"${APP_PATH}\""))
        }
        let macAppStoreScript = try scriptSource("build-luxel-mas-pkg.sh", root: root)
        #expect(
            macAppStoreScript.contains(
                "bash \"${SPEAKER_DIARIZATION_MODEL_AUDITOR}\" \"${PKG_PATH}\""))
    }

    @Test("signed app scripts require and audit bundled Studio Voice resources")
    func signedAppScriptsRequireAndAuditBundledStudioVoiceResources() throws {
        let root = try sharedPackageRootURL()
        try runAudit(
            root: root,
            script: "audit-studio-voice-model.sh",
            modelDirectory: "studio-voice"
        )

        for scriptName in ["build-luxel-app.sh", "build-luxel-mas-pkg.sh"] {
            let script = try scriptSource(scriptName, root: root)
            #expect(script.contains("audit-studio-voice-model.sh"))
            #expect(
                script.contains(
                    "bash \"${STUDIO_VOICE_MODEL_AUDITOR}\" \"${APP_PATH}\""))
        }
        let macAppStoreScript = try scriptSource("build-luxel-mas-pkg.sh", root: root)
        #expect(
            macAppStoreScript.contains(
                "bash \"${STUDIO_VOICE_MODEL_AUDITOR}\" \"${PKG_PATH}\""))
    }

    @Test("MODNet conversion isolates source and validates retained compiler output")
    func modnetConversionIsolatesSourceAndValidatesRetainedOutput() throws {
        let root = try sharedPackageRootURL()
        let driver = try String(
            contentsOf: root.appending(path: "Vendor/Models/modnet-tools/convert.sh"),
            encoding: .utf8
        )
        let converter = try String(
            contentsOf: root.appending(path: "Vendor/Models/modnet-tools/convert_modnet.py"),
            encoding: .utf8
        )

        #expect(driver.contains("RUN_ROOT=\"$(mktemp -d"))
        #expect(driver.contains("core.hooksPath=/dev/null"))
        #expect(driver.contains("status --porcelain=v1 --untracked-files=all"))
        #expect(!driver.contains("${WORK_ROOT}/MODNet"))
        #expect(driver.contains("--require-hashes"))
        #expect(driver.contains("EXPECTED_XCODE_OUTPUT"))
        #expect(driver.contains("COREMLCOMPILER_SHA256"))
        #expect(driver.contains("--validate-compiled \"${VENDORED_MODEL}\""))
        for artifact in [
            "analytics/coremldata.bin",
            "coremldata.bin",
            "metadata.json",
            "model.mil",
            "weights/weight.bin"
        ] {
            #expect(driver.contains("\"\(artifact)\""))
        }
        #expect(converter.contains("compute_units=ct.ComputeUnit.ALL"))
        #expect(converter.contains("\"files\": sha256_files(compiled_path)"))
        #expect(!converter.contains("Image.fromarray(difference"))
    }

    private func runAudit(root: URL, script: String, modelDirectory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            root.appending(path: "Scripts/\(script)").path,
            root.appending(path: "Vendor/Models/\(modelDirectory)").path
        ]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    private func scriptSource(_ scriptName: String, root: URL) throws -> String {
        try String(
            contentsOf: root.appending(path: "Scripts/\(scriptName)"),
            encoding: .utf8
        )
    }
}
