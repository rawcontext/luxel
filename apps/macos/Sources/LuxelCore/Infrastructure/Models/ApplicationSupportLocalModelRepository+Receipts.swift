import Foundation

extension ApplicationSupportLocalModelRepository {
    func installationReceipt(
        descriptor: LocalModelDescriptor,
        validatorVersion: Int,
        installedAt: Date
    ) -> InstallationReceipt {
        let release = descriptor.currentRelease
        return InstallationReceipt(
            schemaVersion: Self.installationSchemaVersion,
            modelID: descriptor.id,
            commit: release.commit,
            repository: release.repository,
            engineRevision: release.engineRevision,
            validatorKey: release.validatorKey,
            validatorVersion: validatorVersion,
            artifacts: release.artifacts.filter(\.retained),
            logicalBytes: release.expectedPayloadBytes,
            allocatedBytes: 0,
            appVersion: appVersion,
            appBuild: appBuild,
            installedAt: installedAt,
            lastValidatedAt: installedAt,
            licenseIdentifier: release.licenseIdentifier,
            attributionIdentifier: release.attributionIdentifier,
            runtimeDirectoryName: release.runtimeDirectoryName
        )
    }

    func validateInstalledFiles(
        at releaseRoot: URL,
        retainedPaths: [String],
        retainedArtifacts: [LocalModelArtifact]
    ) throws {
        do {
            try validateExactFiles(
                at: releaseRoot,
                expectedPaths: Set(["installation.json"] + retainedPaths),
                expectedSizes: Dictionary(
                    uniqueKeysWithValues: zip(retainedPaths, retainedArtifacts.map(\.byteCount))
                )
            )
        } catch {
            throw LocalModelFailure.installationCorrupt("Installed model files changed")
        }
    }

    func readInstallationReceipt(at receiptURL: URL) throws -> InstallationReceipt {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(
                InstallationReceipt.self,
                from: Data(contentsOf: receiptURL)
            )
        } catch {
            throw LocalModelFailure.installationCorrupt("Installation receipt is unreadable")
        }
    }
}
