import Foundation
import LuxelCore
import Testing

@Suite("Downloaded model catalog")
struct LocalModelCatalogTests {
    @Test("production Precision release is complete and commit pinned")
    func productionPrecisionReleaseIsCompleteAndCommitPinned() throws {
        let catalog = try BundledLocalModelCatalog.production(
            registeredValidatorKeys: [ParakeetPrecisionModelValidator.validatorKey],
            attributionIdentifiers: ["fluidinference-parakeet-tdt-0.6b-v3-coreml"]
        ).catalog()

        #expect(catalog.schemaVersion == 1)
        let descriptor = try #require(catalog.models.first)
        let release = descriptor.currentRelease
        #expect(descriptor.id == PrecisionTranscriptionEngine.modelID)
        #expect(release.commit == "aed02740059203c4a87495924f685de3722ae9ce")
        #expect(release.repository == "FluidInference/parakeet-tdt-0.6b-v3-coreml")
        #expect(
            release.runtimeDirectoryName == ParakeetPrecisionModelValidator.runtimeDirectoryName)
        #expect(release.expectedPayloadBytes == 483_105_645)
        #expect(release.artifactCount == 21)
        #expect(release.artifacts.count == 21)
        #expect(release.artifacts.reduce(0) { $0 + $1.byteCount } == 483_105_645)
        #expect(release.artifacts.allSatisfy { $0.sha256.count == 64 })
        #expect(release.artifacts.map(\.path) == release.artifacts.map(\.path).sorted())
        #expect(
            Set(release.supportedLanguageCodes) == PrecisionTranscriptionLanguageCatalog.supportedCodes)
    }

    @Test(
        "catalog rejects unsafe paths and executable artifacts",
        arguments: [
            "../escape.bin", "/absolute.bin", "safe/../escape.bin", "script.sh", "bad\\alias.bin"
        ])
    func catalogRejectsUnsafePathsAndExecutableArtifacts(path: String) throws {
        let catalog = try fixtureCatalog(paths: [path])
        #expect(throws: LocalModelCatalogError.self) {
            try BundledLocalModelCatalog.validate(
                catalog,
                registeredValidatorKeys: [fixtureValidatorKey],
                attributionIdentifiers: ["fixture"],
                approvedOrigins: ["huggingface.co", "creativecommons.org"]
            )
        }
    }

    @Test("catalog rejects case-folding collisions")
    func catalogRejectsCaseFoldingCollisions() throws {
        let catalog = try fixtureCatalog(paths: ["Model/data.bin", "model/data.bin"])
        #expect(throws: LocalModelCatalogError.self) {
            try BundledLocalModelCatalog.validate(
                catalog,
                registeredValidatorKeys: [fixtureValidatorKey],
                attributionIdentifiers: ["fixture"],
                approvedOrigins: ["huggingface.co", "creativecommons.org"]
            )
        }
    }

    @Test("model IDs enforce the conservative ASCII grammar")
    func modelIDsEnforceConservativeASCIIGrammar() throws {
        #expect(LocalModelID(rawValue: "model.valid-1") != nil)
        #expect(LocalModelID(rawValue: "Model.Invalid") == nil)
        #expect(LocalModelID(rawValue: "-invalid") == nil)
        #expect(LocalModelID(rawValue: "model_with_underscore") == nil)
        #expect(LocalModelID(rawValue: "mødel") == nil)
    }

    @Test("catalog rejects releases outside the current app compatibility range")
    func catalogRejectsIncompatibleAppVersions() throws {
        let catalog = try fixtureCatalog(paths: ["payload.bin"], minimumAppVersion: "2.0.0")
        #expect(
            throws: LocalModelCatalogError.incompatibleAppVersion(
                minimum: "2.0.0",
                maximum: nil,
                current: "1.5.0"
            )
        ) {
            try BundledLocalModelCatalog.validate(
                catalog,
                registeredValidatorKeys: [fixtureValidatorKey],
                attributionIdentifiers: ["fixture"],
                approvedOrigins: ["huggingface.co", "creativecommons.org"],
                currentAppVersion: "1.5.0"
            )
        }
    }

    @Test("catalog rejects unsupported schemas digests validators and attributions")
    func catalogRejectsMalformedTrustMetadata() throws {
        let unsupportedSchema = try fixtureCatalog(
            paths: ["payload.bin"],
            schemaVersion: 2
        )
        #expect(throws: LocalModelCatalogError.unsupportedSchema(2)) {
            try validateFixture(unsupportedSchema)
        }

        let invalidDigest = try fixtureCatalog(
            paths: ["payload.bin"],
            digest: String(repeating: "A", count: 64)
        )
        #expect(throws: LocalModelCatalogError.self) {
            try validateFixture(invalidDigest)
        }

        let valid = try fixtureCatalog(paths: ["payload.bin"])
        #expect(throws: LocalModelCatalogError.missingValidator("fixture")) {
            try BundledLocalModelCatalog.validate(
                valid,
                registeredValidatorKeys: [],
                attributionIdentifiers: ["fixture"],
                approvedOrigins: ["huggingface.co", "creativecommons.org"]
            )
        }
        #expect(throws: LocalModelCatalogError.missingAttribution("fixture")) {
            try BundledLocalModelCatalog.validate(
                valid,
                registeredValidatorKeys: [fixtureValidatorKey],
                attributionIdentifiers: [],
                approvedOrigins: ["huggingface.co", "creativecommons.org"]
            )
        }
    }

    private var fixtureValidatorKey: LocalModelValidatorKey {
        LocalModelValidatorKey(rawValue: "fixture")
    }

    private func fixtureCatalog(
        paths: [String],
        minimumAppVersion: String = "1.0.0",
        schemaVersion: Int = 1,
        digest: String = String(repeating: "a", count: 64)
    ) throws -> LocalModelCatalog {
        let artifacts = paths.map {
            LocalModelArtifact(
                path: $0,
                byteCount: 1,
                sha256: digest,
                kind: .auxiliaryData
            )
        }
        let release = LocalModelRelease(
            provider: .huggingFace,
            repository: "Fixture/model",
            commit: String(repeating: "a", count: 40),
            upstreamVersion: "fixture",
            engineRevision: "fixture-v1",
            validatorKey: fixtureValidatorKey,
            minimumValidatorVersion: 1,
            minimumAppVersion: minimumAppVersion,
            licenseIdentifier: "CC0-1.0",
            licenseDisplayName: "CC0",
            attributionIdentifier: "fixture",
            modelCardURL: URL(string: "https://huggingface.co/Fixture/model")!,
            expectedPayloadBytes: Int64(artifacts.count),
            requiredFreeBytes: Int64(artifacts.count + 1),
            artifactCount: artifacts.count,
            artifacts: artifacts,
            runtimeDirectoryName: "fixture-model"
        )
        return LocalModelCatalog(
            schemaVersion: schemaVersion,
            generatedAt: Date(timeIntervalSince1970: 0),
            models: [
                LocalModelDescriptor(
                    id: LocalModelID(rawValue: "fixture.model")!,
                    displayNameKey: "display",
                    featureNameKey: "feature",
                    summaryKey: "summary",
                    downloadDisclosureKey: "download",
                    removalWarningKey: "remove",
                    category: "test",
                    mayBeShared: false,
                    licenseURL: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!,
                    currentRelease: release
                )
            ]
        )
    }

    private func validateFixture(_ catalog: LocalModelCatalog) throws {
        try BundledLocalModelCatalog.validate(
            catalog,
            registeredValidatorKeys: [fixtureValidatorKey],
            attributionIdentifiers: ["fixture"],
            approvedOrigins: ["huggingface.co", "creativecommons.org"]
        )
    }
}
