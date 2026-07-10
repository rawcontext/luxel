import Foundation

public final class ApplicationSupportLocalModelRepository: LocalModelRepository, @unchecked Sendable {
    public static let installationSchemaVersion = 1

    let root: URL
    let fileManager: FileManager
    let appVersion: String
    let appBuild: String
    let now: @Sendable () -> Date

    public init(
        root: URL,
        fileManager: FileManager = .default,
        appVersion: String,
        appBuild: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.fileManager = fileManager
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.now = now
    }

    public func reconcile(
        descriptor: LocalModelDescriptor,
        validatorVersion: Int
    ) throws -> LocalModelInstallation? {
        try ensureRoot()
        try removeStaleStaging(for: descriptor.id)

        let recognizedReleases = [descriptor.currentRelease, descriptor.previousRelease].compactMap {
            $0
        }
        for release in recognizedReleases {
            let releaseRoot = try releaseRoot(for: descriptor.id, commit: release.commit)
            guard fileManager.fileExists(atPath: releaseRoot.path) else {
                continue
            }
            return try fastReadyCheck(
                descriptor: descriptor,
                release: release,
                validatorVersion: validatorVersion
            )
        }
        return nil
    }

    public func beginStaging(for id: LocalModelID) throws -> LocalModelStagingArea {
        try ensureRoot()
        let operationID = UUID()
        let operationRoot = try modelRoot(for: id)
            .appending(path: "staging", directoryHint: .isDirectory)
            .appending(path: operationID.uuidString, directoryHint: .isDirectory)
        let source = operationRoot.appending(path: "source", directoryHint: .isDirectory)
        let prepared = operationRoot.appending(path: "prepared", directoryHint: .isDirectory)
        try createPrivateDirectory(at: source)
        try createPrivateDirectory(at: prepared)
        try write(
            StagingOperationReceipt(
                schemaVersion: Self.installationSchemaVersion,
                modelID: id,
                operationID: operationID,
                createdAt: now()
            ),
            to: operationRoot.appending(path: "operation.json")
        )
        return LocalModelStagingArea(
            operationID: operationID,
            sourceRoot: source,
            preparedRoot: prepared
        )
    }

    public func artifactURL(
        _ artifact: LocalModelArtifact,
        in staging: LocalModelStagingArea
    ) throws -> URL {
        let url = staging.sourceRoot.appending(path: artifact.path)
        try requireDescendant(url, of: staging.sourceRoot)
        try createPrivateDirectory(at: url.deletingLastPathComponent())
        return url
    }

    public func validateExactSourceFiles(
        release: LocalModelRelease,
        staging: LocalModelStagingArea
    ) throws {
        try validateExactFiles(
            at: staging.sourceRoot,
            expectedPaths: Set(release.artifacts.map(\.path))
        )
    }

    public func promote(
        descriptor: LocalModelDescriptor,
        staging: LocalModelStagingArea,
        prepared: LocalModelPreparedPayload,
        validatorVersion: Int
    ) throws -> LocalModelInstallation {
        let release = descriptor.currentRelease
        try requireDescendant(prepared.payloadRoot, of: staging.preparedRoot)
        try validateExactFiles(
            at: prepared.payloadRoot,
            expectedPaths: Set(
                release.artifacts.filter(\.retained).map {
                    "\(release.runtimeDirectoryName)/\($0.path)"
                }
            )
        )

        let releasesRoot = try modelRoot(for: descriptor.id)
            .appending(path: "releases", directoryHint: .isDirectory)
        try createPrivateDirectory(at: releasesRoot)
        let finalRoot = try releaseRoot(for: descriptor.id, commit: release.commit)
        if fileManager.fileExists(atPath: finalRoot.path) {
            discard(staging)
            return try fastReadyCheck(
                descriptor: descriptor,
                release: release,
                validatorVersion: validatorVersion
            )
        }

        let promotionRoot = releasesRoot.appending(
            path: ".promoting-\(staging.operationID.uuidString)",
            directoryHint: .isDirectory
        )
        try createPrivateDirectory(at: promotionRoot)
        let payloadRoot = promotionRoot.appending(path: "payload", directoryHint: .isDirectory)
        try fileManager.moveItem(at: prepared.payloadRoot, to: payloadRoot)

        let installedAt = now()
        var receipt = installationReceipt(
            descriptor: descriptor,
            validatorVersion: validatorVersion,
            installedAt: installedAt
        )
        let receiptURL = promotionRoot.appending(path: "installation.json")
        try write(receipt, to: receiptURL)
        receipt.allocatedBytes = try allocatedBytes(at: promotionRoot)
        try write(receipt, to: receiptURL)
        try prohibitExecutableContent(at: promotionRoot)
        try markExcludedFromBackup(promotionRoot)
        try fileManager.moveItem(at: promotionRoot, to: finalRoot)
        discard(staging)
        return try fastReadyCheck(
            descriptor: descriptor,
            release: release,
            validatorVersion: validatorVersion
        )
    }

    public func discard(_ staging: LocalModelStagingArea) {
        let operationRoot = staging.sourceRoot.deletingLastPathComponent()
        try? fileManager.removeItem(at: operationRoot)
        removeIfEmpty(operationRoot.deletingLastPathComponent())
        removeIfEmpty(operationRoot.deletingLastPathComponent().deletingLastPathComponent())
    }

    public func remove(_ installation: LocalModelInstallation) throws {
        let modelRoot = try modelRoot(for: installation.modelID)
        guard fileManager.fileExists(atPath: modelRoot.path) else {
            return
        }
        let deletionRoot = root.appending(
            path: ".deleting-\(installation.modelID.rawValue)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.moveItem(at: modelRoot, to: deletionRoot)
        do {
            try fileManager.removeItem(at: deletionRoot)
        } catch {
            throw LocalModelFailure.storageFailure("Could not finish removing the model")
        }
    }

    public func availableCapacity() throws -> Int64 {
        try ensureRoot()
        let values = try root.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ])
        if let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        return Int64(values.volumeAvailableCapacity ?? 0)
    }

    private func fastReadyCheck(
        descriptor: LocalModelDescriptor,
        release: LocalModelRelease,
        validatorVersion: Int
    ) throws -> LocalModelInstallation {
        let releaseRoot = try releaseRoot(for: descriptor.id, commit: release.commit)
        let receiptURL = releaseRoot.appending(path: "installation.json")
        let payloadRoot = releaseRoot.appending(path: "payload", directoryHint: .isDirectory)
        let retainedArtifacts = release.artifacts.filter(\.retained)
        let retainedPaths = retainedArtifacts.map {
            "payload/\(release.runtimeDirectoryName)/\($0.path)"
        }
        try validateInstalledFiles(
            at: releaseRoot,
            retainedPaths: retainedPaths,
            retainedArtifacts: retainedArtifacts
        )
        let receipt = try readInstallationReceipt(at: receiptURL)

        guard receipt.schemaVersion == Self.installationSchemaVersion,
              receipt.modelID == descriptor.id,
              receipt.commit == release.commit,
              receipt.repository == release.repository,
              receipt.engineRevision == release.engineRevision,
              receipt.validatorKey == release.validatorKey,
              receipt.validatorVersion >= max(validatorVersion, release.minimumValidatorVersion),
              receipt.artifacts == release.artifacts.filter(\.retained),
              receipt.runtimeDirectoryName == release.runtimeDirectoryName
        else {
            throw LocalModelFailure.installationCorrupt("Installation receipt does not match the catalog")
        }

        return LocalModelInstallation(
            modelID: descriptor.id,
            commit: receipt.commit,
            engineRevision: receipt.engineRevision,
            payloadRoot: payloadRoot,
            logicalBytes: receipt.logicalBytes,
            allocatedBytes: try allocatedBytes(at: releaseRoot),
            validatorKey: receipt.validatorKey,
            validatorVersion: receipt.validatorVersion,
            installedAt: receipt.installedAt
        )
    }

}

struct StagingOperationReceipt: Codable {
    let schemaVersion: Int
    let modelID: LocalModelID
    let operationID: UUID
    let createdAt: Date
}

struct InstallationReceipt: Codable {
    let schemaVersion: Int
    let modelID: LocalModelID
    let commit: String
    let repository: String
    let engineRevision: String
    let validatorKey: LocalModelValidatorKey
    let validatorVersion: Int
    let artifacts: [LocalModelArtifact]
    let logicalBytes: Int64
    var allocatedBytes: Int64
    let appVersion: String
    let appBuild: String
    let installedAt: Date
    let lastValidatedAt: Date
    let licenseIdentifier: String
    let attributionIdentifier: String
    let runtimeDirectoryName: String
}
