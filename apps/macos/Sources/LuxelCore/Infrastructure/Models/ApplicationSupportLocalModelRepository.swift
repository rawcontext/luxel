import Foundation

public final class ApplicationSupportLocalModelRepository: LocalModelRepository, @unchecked Sendable {
    public static let installationSchemaVersion = 1

    private let root: URL
    private let fileManager: FileManager
    private let appVersion: String
    private let appBuild: String
    private let now: @Sendable () -> Date

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
        var receipt = InstallationReceipt(
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
        do {
            try validateExactFiles(
                at: releaseRoot,
                expectedPaths: Set(["installation.json"] + retainedPaths),
                expectedSizes: Dictionary(
                    uniqueKeysWithValues: zip(
                        retainedPaths,
                        retainedArtifacts.map(\.byteCount)
                    ))
            )
        } catch {
            throw LocalModelFailure.installationCorrupt("Installed model files changed")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let receipt: InstallationReceipt
        do {
            receipt = try decoder.decode(
                InstallationReceipt.self,
                from: Data(contentsOf: receiptURL)
            )
        } catch {
            throw LocalModelFailure.installationCorrupt("Installation receipt is unreadable")
        }

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

private extension ApplicationSupportLocalModelRepository {
    private func validateExactFiles(
        at root: URL,
        expectedPaths: Set<String>,
        expectedSizes: [String: Int64] = [:]
    ) throws {
        var actualPaths = Set<String>()
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        else {
            throw LocalModelFailure.unexpectedFileSet
        }

        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey
            ])
            guard values.isSymbolicLink != true else {
                throw LocalModelFailure.invalidFileType
            }
            if values.isDirectory == true {
                continue
            }
            guard values.isRegularFile == true else {
                throw LocalModelFailure.invalidFileType
            }
            try prohibitExecutableFile(at: url)
            let relative = relativePath(of: url, under: root)
            actualPaths.insert(relative)
            if let expectedSize = expectedSizes[relative] {
                let attributes = try fileManager.attributesOfItem(atPath: url.path)
                let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                guard actualSize == expectedSize else {
                    throw LocalModelFailure.unexpectedByteCount(
                        expected: expectedSize,
                        actual: actualSize
                    )
                }
            }
        }
        guard actualPaths == expectedPaths else {
            throw LocalModelFailure.unexpectedFileSet
        }
    }

    private func prohibitExecutableContent(at root: URL) throws {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        else {
            throw LocalModelFailure.invalidFileType
        }
        for case let url as URL in enumerator {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                continue
            }
            if !isDirectory.boolValue {
                try prohibitExecutableFile(at: url)
            }
        }
    }

    private func prohibitExecutableFile(at url: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
        guard permissions & 0o111 == 0 else {
            throw LocalModelFailure.invalidFileType
        }
        let links = (attributes[.referenceCount] as? NSNumber)?.intValue ?? 1
        guard links <= 1 else {
            throw LocalModelFailure.invalidFileType
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 4) ?? Data()
        let forbiddenMagic: Set<[UInt8]> = [
            [0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
            [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
            [0xca, 0xfe, 0xba, 0xbe]
        ]
        guard !forbiddenMagic.contains(Array(prefix)),
              !prefix.starts(with: Data([0x23, 0x21]))
        else {
            throw LocalModelFailure.invalidFileType
        }
    }

    private func ensureRoot() throws {
        try createPrivateDirectory(at: root)
        try markExcludedFromBackup(root)
    }

    private func createPrivateDirectory(at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var current = directory.standardizedFileURL.resolvingSymlinksInPath()
        while current.path == root.path || current.path.hasPrefix(root.path + "/") {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: current.path
            )
            if current.path == root.path { break }
            current = current.deletingLastPathComponent()
        }
    }

    private func markExcludedFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        guard
            try mutableURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        else {
            throw LocalModelFailure.storageFailure("Could not exclude model storage from backup")
        }
    }

    private func removeStaleStaging(for id: LocalModelID) throws {
        let stagingRoot = try modelRoot(for: id)
            .appending(path: "staging", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: stagingRoot.path) else {
            return
        }
        try fileManager.removeItem(at: stagingRoot)
    }

    private func modelRoot(for id: LocalModelID) throws -> URL {
        let url = root.appending(path: id.rawValue, directoryHint: .isDirectory)
        try requireDescendant(url, of: root)
        return url
    }

    private func releaseRoot(for id: LocalModelID, commit: String) throws -> URL {
        let url = try modelRoot(for: id)
            .appending(path: "releases", directoryHint: .isDirectory)
            .appending(path: commit, directoryHint: .isDirectory)
        try requireDescendant(url, of: root)
        return url
    }

    private func requireDescendant(_ candidate: URL, of parent: URL) throws {
        let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard candidatePath == parentPath || candidatePath.hasPrefix(parentPath + "/") else {
            throw LocalModelFailure.storagePermission
        }
    }

    private func removeIfEmpty(_ directory: URL) {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ), contents.isEmpty
        else {
            return
        }
        try? fileManager.removeItem(at: directory)
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private func allocatedBytes(at root: URL) throws -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ]
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys)
            )
        else {
            return 0
        }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: [.atomic])
    }
}

private struct StagingOperationReceipt: Codable {
    let schemaVersion: Int
    let modelID: LocalModelID
    let operationID: UUID
    let createdAt: Date
}

private struct InstallationReceipt: Codable {
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
