import Foundation

public struct LocalModelID: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public init(validating rawValue: String) throws {
        guard Self.isValid(rawValue) else {
            throw LocalModelCatalogError.invalidModelID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        try self.init(validating: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func isValid(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count),
              let first = value.utf8.first,
              (first >= Character("a").asciiValue! && first <= Character("z").asciiValue!)
                || (first >= Character("0").asciiValue! && first <= Character("9").asciiValue!)
        else {
            return false
        }

        return value.utf8.allSatisfy {
            ($0 >= Character("a").asciiValue! && $0 <= Character("z").asciiValue!)
                || ($0 >= Character("0").asciiValue! && $0 <= Character("9").asciiValue!)
                || $0 == Character(".").asciiValue!
                || $0 == Character("-").asciiValue!
        }
    }
}

public struct LocalModelValidatorKey: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum LocalModelProvider: String, Codable, Equatable, Sendable {
    case huggingFace
}

public enum LocalModelArtifactKind: String, Codable, Equatable, Sendable {
    case coreMLModelData
    case vocabulary
    case jsonConfiguration
    case textMetadata
    case auxiliaryData
    case safetensors
}

public struct LocalModelArtifact: Codable, Equatable, Sendable {
    public let path: String
    public let byteCount: Int64
    public let sha256: String
    public let kind: LocalModelArtifactKind
    public let retained: Bool

    public init(
        path: String,
        byteCount: Int64,
        sha256: String,
        kind: LocalModelArtifactKind,
        retained: Bool = true
    ) {
        self.path = path
        self.byteCount = byteCount
        self.sha256 = sha256
        self.kind = kind
        self.retained = retained
    }
}

public struct LocalModelRelease: Codable, Equatable, Sendable {
    public let provider: LocalModelProvider
    public let repository: String
    public let commit: String
    public let upstreamVersion: String
    public let engineRevision: String
    public let validatorKey: LocalModelValidatorKey
    public let minimumValidatorVersion: Int
    public let minimumAppVersion: String
    public let maximumAppVersion: String?
    public let licenseIdentifier: String
    public let licenseDisplayName: String
    public let attributionIdentifier: String
    public let modelCardURL: URL
    public let expectedPayloadBytes: Int64
    public let requiredFreeBytes: Int64
    public let artifactCount: Int
    public let artifacts: [LocalModelArtifact]
    public let supportedLanguageCodes: [String]
    public let runtimeDirectoryName: String

    public init(
        provider: LocalModelProvider,
        repository: String,
        commit: String,
        upstreamVersion: String,
        engineRevision: String,
        validatorKey: LocalModelValidatorKey,
        minimumValidatorVersion: Int,
        minimumAppVersion: String,
        maximumAppVersion: String? = nil,
        licenseIdentifier: String,
        licenseDisplayName: String,
        attributionIdentifier: String,
        modelCardURL: URL,
        expectedPayloadBytes: Int64,
        requiredFreeBytes: Int64,
        artifactCount: Int,
        artifacts: [LocalModelArtifact],
        supportedLanguageCodes: [String] = [],
        runtimeDirectoryName: String
    ) {
        self.provider = provider
        self.repository = repository
        self.commit = commit
        self.upstreamVersion = upstreamVersion
        self.engineRevision = engineRevision
        self.validatorKey = validatorKey
        self.minimumValidatorVersion = minimumValidatorVersion
        self.minimumAppVersion = minimumAppVersion
        self.maximumAppVersion = maximumAppVersion
        self.licenseIdentifier = licenseIdentifier
        self.licenseDisplayName = licenseDisplayName
        self.attributionIdentifier = attributionIdentifier
        self.modelCardURL = modelCardURL
        self.expectedPayloadBytes = expectedPayloadBytes
        self.requiredFreeBytes = requiredFreeBytes
        self.artifactCount = artifactCount
        self.artifacts = artifacts
        self.supportedLanguageCodes = supportedLanguageCodes
        self.runtimeDirectoryName = runtimeDirectoryName
    }
}

public struct LocalModelDescriptor: Codable, Equatable, Sendable {
    public let id: LocalModelID
    public let displayNameKey: String
    public let featureNameKey: String
    public let summaryKey: String
    public let downloadDisclosureKey: String
    public let removalWarningKey: String
    public let category: String
    public let mayBeShared: Bool
    public let licenseURL: URL
    public let currentRelease: LocalModelRelease
    public let previousRelease: LocalModelRelease?

    public init(
        id: LocalModelID,
        displayNameKey: String,
        featureNameKey: String,
        summaryKey: String,
        downloadDisclosureKey: String,
        removalWarningKey: String,
        category: String,
        mayBeShared: Bool,
        licenseURL: URL,
        currentRelease: LocalModelRelease,
        previousRelease: LocalModelRelease? = nil
    ) {
        self.id = id
        self.displayNameKey = displayNameKey
        self.featureNameKey = featureNameKey
        self.summaryKey = summaryKey
        self.downloadDisclosureKey = downloadDisclosureKey
        self.removalWarningKey = removalWarningKey
        self.category = category
        self.mayBeShared = mayBeShared
        self.licenseURL = licenseURL
        self.currentRelease = currentRelease
        self.previousRelease = previousRelease
    }
}

public struct LocalModelCatalog: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let models: [LocalModelDescriptor]

    public init(schemaVersion: Int, generatedAt: Date, models: [LocalModelDescriptor]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.models = models
    }
}

public enum LocalModelPhase: String, Codable, Equatable, Sendable {
    case queued
    case downloading
    case verifying
    case preparing
    case validating
}

public struct LocalModelProgress: Equatable, Sendable {
    public let phase: LocalModelPhase
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let currentArtifact: String?

    public init(
        phase: LocalModelPhase,
        completedBytes: Int64,
        totalBytes: Int64,
        currentArtifact: String? = nil
    ) {
        self.phase = phase
        self.completedBytes = min(max(completedBytes, 0), max(totalBytes, 0))
        self.totalBytes = max(totalBytes, 0)
        self.currentArtifact = currentArtifact
    }

    public var fractionCompleted: Double {
        totalBytes > 0 ? Double(completedBytes) / Double(totalBytes) : 0
    }
}

public struct LocalModelInstallation: Codable, Equatable, Sendable {
    public let modelID: LocalModelID
    public let commit: String
    public let engineRevision: String
    public let payloadRoot: URL
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let validatorKey: LocalModelValidatorKey
    public let validatorVersion: Int
    public let installedAt: Date

    public init(
        modelID: LocalModelID,
        commit: String,
        engineRevision: String,
        payloadRoot: URL,
        logicalBytes: Int64,
        allocatedBytes: Int64,
        validatorKey: LocalModelValidatorKey,
        validatorVersion: Int,
        installedAt: Date
    ) {
        self.modelID = modelID
        self.commit = commit
        self.engineRevision = engineRevision
        self.payloadRoot = payloadRoot
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.validatorKey = validatorKey
        self.validatorVersion = validatorVersion
        self.installedAt = installedAt
    }
}

public enum LocalModelFailure: Error, Equatable, Sendable {
    case invalidCatalog(String)
    case unavailableInAppVersion
    case insufficientDiskSpace(required: Int64, available: Int64)
    case networkUnavailable
    case transport(String)
    case httpStatus(Int)
    case rateLimited
    case forbiddenRedirect
    case responseTooLarge
    case unexpectedByteCount(expected: Int64, actual: Int64)
    case checksumMismatch
    case invalidFileType
    case unexpectedFileSet
    case storagePermission
    case storageFailure(String)
    case preparationFailed(String)
    case validationFailed(String)
    case installationCorrupt(String)
    case inUse
    case canceled
    case notInstalled
}

public enum LocalModelInstallationState: Equatable, Sendable {
    case notInstalled(expectedDownloadBytes: Int64, requiredFreeBytes: Int64)
    case queued(position: Int)
    case downloading(LocalModelProgress)
    case verifying(LocalModelProgress)
    case preparing(LocalModelProgress?)
    case validating
    case ready(LocalModelInstallation)
    case updateAvailable(installed: LocalModelInstallation, available: LocalModelRelease)
    case repairRequired(LocalModelInstallation?, LocalModelFailure)
    case canceling
    case removing
    case failed(LocalModelFailure, priorReadyInstallation: LocalModelInstallation?)
}

public struct LocalModelStateChange: Equatable, Sendable {
    public let modelID: LocalModelID
    public let state: LocalModelInstallationState
    public let generation: UInt64

    public init(modelID: LocalModelID, state: LocalModelInstallationState, generation: UInt64) {
        self.modelID = modelID
        self.state = state
        self.generation = generation
    }
}

public struct LocalModelLease: Equatable, Hashable, Sendable {
    public let token: UUID
    public let modelID: LocalModelID
    public let commit: String
    public let payloadRoot: URL
    public let validatorKey: LocalModelValidatorKey

    public init(
        token: UUID,
        modelID: LocalModelID,
        commit: String,
        payloadRoot: URL,
        validatorKey: LocalModelValidatorKey
    ) {
        self.token = token
        self.modelID = modelID
        self.commit = commit
        self.payloadRoot = payloadRoot
        self.validatorKey = validatorKey
    }
}

public enum LocalModelRuntimeInvalidation: Equatable, Sendable {
    case missingFile
    case corruptFile
    case loadFailed
}

public enum LocalModelCatalogError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidModelID(String)
    case duplicateModelID(String)
    case invalidRepository(String)
    case invalidCommit(String)
    case invalidDigest(String)
    case invalidPath(String)
    case duplicatePath(String)
    case caseCollidingPath(String)
    case invalidTotals
    case incompatibleAppVersion(minimum: String, maximum: String?, current: String)
    case unsupportedURL(String)
    case forbiddenArtifact(String)
    case missingAttribution(String)
    case missingValidator(String)
}
