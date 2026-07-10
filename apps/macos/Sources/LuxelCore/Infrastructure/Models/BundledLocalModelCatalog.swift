import Foundation

public struct BundledLocalModelCatalog: LocalModelCatalogProviding, Sendable {
    public static let schemaVersion = 1

    private let resourceURL: URL
    private let registeredValidatorKeys: Set<LocalModelValidatorKey>
    private let attributionIdentifiers: Set<String>
    private let approvedOrigins: Set<String>
    private let currentAppVersion: String

    public init(
        resourceURL: URL,
        registeredValidatorKeys: Set<LocalModelValidatorKey>,
        attributionIdentifiers: Set<String>,
        approvedOrigins: Set<String> = ["huggingface.co", "creativecommons.org"],
        currentAppVersion: String = "1.0.0"
    ) {
        self.resourceURL = resourceURL
        self.registeredValidatorKeys = registeredValidatorKeys
        self.attributionIdentifiers = attributionIdentifiers
        self.approvedOrigins = approvedOrigins
        self.currentAppVersion = currentAppVersion
    }

    public static func production(
        registeredValidatorKeys: Set<LocalModelValidatorKey>,
        attributionIdentifiers: Set<String>,
        currentAppVersion: String = "1.0.0"
    ) throws -> BundledLocalModelCatalog {
        guard
            let url = Bundle.module.url(
                forResource: "model-catalog",
                withExtension: "json"
            )
        else {
            throw LocalModelCatalogError.invalidPath("Models/model-catalog.json")
        }

        return BundledLocalModelCatalog(
            resourceURL: url,
            registeredValidatorKeys: registeredValidatorKeys,
            attributionIdentifiers: attributionIdentifiers,
            currentAppVersion: currentAppVersion
        )
    }

    public func catalog() throws -> LocalModelCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(
            LocalModelCatalog.self,
            from: Data(contentsOf: resourceURL)
        )
        try Self.validate(
            catalog,
            registeredValidatorKeys: registeredValidatorKeys,
            attributionIdentifiers: attributionIdentifiers,
            approvedOrigins: approvedOrigins,
            currentAppVersion: currentAppVersion
        )
        return catalog
    }

    public static func validate(
        _ catalog: LocalModelCatalog,
        registeredValidatorKeys: Set<LocalModelValidatorKey>,
        attributionIdentifiers: Set<String>,
        approvedOrigins: Set<String>,
        currentAppVersion: String = "1.0.0"
    ) throws {
        guard catalog.schemaVersion == schemaVersion else {
            throw LocalModelCatalogError.unsupportedSchema(catalog.schemaVersion)
        }

        var modelIDs = Set<LocalModelID>(); var releaseIdentities = Set<String>()
        for descriptor in catalog.models {
            guard modelIDs.insert(descriptor.id).inserted else {
                throw LocalModelCatalogError.duplicateModelID(descriptor.id.rawValue)
            }
            guard
                [
                    descriptor.displayNameKey,
                    descriptor.featureNameKey,
                    descriptor.summaryKey,
                    descriptor.downloadDisclosureKey,
                    descriptor.removalWarningKey,
                    descriptor.category
                ].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            else {
                throw LocalModelCatalogError.invalidModelID(descriptor.id.rawValue)
            }
            try validate(
                descriptor.currentRelease,
                registeredValidatorKeys: registeredValidatorKeys,
                attributionIdentifiers: attributionIdentifiers,
                approvedOrigins: approvedOrigins,
                currentAppVersion: currentAppVersion
            )
            let currentIdentity =
                "\(descriptor.currentRelease.repository)@\(descriptor.currentRelease.commit)"
            guard releaseIdentities.insert(currentIdentity).inserted else {
                throw LocalModelCatalogError.invalidCommit(descriptor.currentRelease.commit)
            }
            if let previousRelease = descriptor.previousRelease {
                try validate(
                    previousRelease,
                    registeredValidatorKeys: registeredValidatorKeys,
                    attributionIdentifiers: attributionIdentifiers,
                    approvedOrigins: approvedOrigins,
                    currentAppVersion: currentAppVersion
                )
                guard previousRelease.commit != descriptor.currentRelease.commit else {
                    throw LocalModelCatalogError.invalidCommit(previousRelease.commit)
                }
                let previousIdentity = "\(previousRelease.repository)@\(previousRelease.commit)"
                guard releaseIdentities.insert(previousIdentity).inserted else {
                    throw LocalModelCatalogError.invalidCommit(previousRelease.commit)
                }
            }
            try validate(url: descriptor.licenseURL, approvedOrigins: approvedOrigins)
        }
    }
}

private extension BundledLocalModelCatalog {
    private static func validate(
        _ release: LocalModelRelease,
        registeredValidatorKeys: Set<LocalModelValidatorKey>,
        attributionIdentifiers: Set<String>,
        approvedOrigins: Set<String>,
        currentAppVersion: String
    ) throws {
        try validateIdentityAndLanguage(release, registeredValidatorKeys: registeredValidatorKeys)
        guard attributionIdentifiers.contains(release.attributionIdentifier) else {
            throw LocalModelCatalogError.missingAttribution(release.attributionIdentifier)
        }
        try validateCompatibility(release, currentAppVersion: currentAppVersion)
        try validate(url: release.modelCardURL, approvedOrigins: approvedOrigins)
        try validatePayload(release)
        try validateArtifacts(release.artifacts)
    }

    private static func validateIdentityAndLanguage(
        _ release: LocalModelRelease,
        registeredValidatorKeys: Set<LocalModelValidatorKey>
    ) throws {
        let repositoryParts = release.repository.split(separator: "/", omittingEmptySubsequences: false)
        guard repositoryParts.count == 2,
              repositoryParts.allSatisfy({ isConservativeIdentifier(String($0)) })
        else {
            throw LocalModelCatalogError.invalidRepository(release.repository)
        }
        guard isLowercaseHex(release.commit, count: 40) else {
            throw LocalModelCatalogError.invalidCommit(release.commit)
        }
        guard registeredValidatorKeys.contains(release.validatorKey) else {
            throw LocalModelCatalogError.missingValidator(release.validatorKey.rawValue)
        }
        guard isConservativeIdentifier(release.validatorKey.rawValue),
              !release.licenseIdentifier.isEmpty,
              !release.licenseDisplayName.isEmpty,
              !release.engineRevision.isEmpty,
              Set(release.supportedLanguageCodes).count == release.supportedLanguageCodes.count,
              release.supportedLanguageCodes.allSatisfy({ code in
                !code.isEmpty && code == code.lowercased()
                    && code.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || $0 == 45 }
              })
        else {
            throw LocalModelCatalogError.invalidTotals
        }
    }

    private static func validateCompatibility(
        _ release: LocalModelRelease,
        currentAppVersion: String
    ) throws {
        guard let minimumVersion = semanticVersion(release.minimumAppVersion),
              let currentVersion = semanticVersion(currentAppVersion),
              !currentVersion.lexicographicallyPrecedes(minimumVersion),
              release.maximumAppVersion.map({ maximum in
                guard let maximumVersion = semanticVersion(maximum) else { return false }
                return !maximumVersion.lexicographicallyPrecedes(minimumVersion)
                    && !maximumVersion.lexicographicallyPrecedes(currentVersion)
              }) ?? true
        else {
            throw LocalModelCatalogError.incompatibleAppVersion(
                minimum: release.minimumAppVersion,
                maximum: release.maximumAppVersion,
                current: currentAppVersion
            )
        }
    }

    private static func validatePayload(_ release: LocalModelRelease) throws {
        guard release.minimumValidatorVersion > 0,
              release.expectedPayloadBytes > 0,
              release.requiredFreeBytes >= release.expectedPayloadBytes,
              release.artifactCount == release.artifacts.count,
              release.artifacts.reduce(Int64(0), { $0 + $1.byteCount })
                == release.expectedPayloadBytes,
              isSafeSingleComponent(release.runtimeDirectoryName)
        else {
            throw LocalModelCatalogError.invalidTotals
        }
    }

    private static func validateArtifacts(_ artifacts: [LocalModelArtifact]) throws {
        var paths = Set<String>()
        var foldedPaths = Set<String>()
        for artifact in artifacts {
            try validate(artifact)
            guard paths.insert(artifact.path).inserted else {
                throw LocalModelCatalogError.duplicatePath(artifact.path)
            }
            let folded = artifact.path.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard foldedPaths.insert(folded).inserted else {
                throw LocalModelCatalogError.caseCollidingPath(artifact.path)
            }
        }
    }

    private static func validate(_ artifact: LocalModelArtifact) throws {
        guard artifact.byteCount > 0,
              isLowercaseHex(artifact.sha256, count: 64),
              artifact.path.precomposedStringWithCanonicalMapping == artifact.path,
              !artifact.path.isEmpty,
              !artifact.path.hasPrefix("/"),
              !artifact.path.contains("\\"),
              !artifact.path.contains("\0")
        else {
            throw LocalModelCatalogError.invalidPath(artifact.path)
        }

        let components = artifact.path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw LocalModelCatalogError.invalidPath(artifact.path)
        }

        let forbiddenExtensions = Set([
            "app", "bundle", "dylib", "framework", "js", "pkg", "plugin", "py", "scpt",
            "sh", "so", "swift", "dmg", "zip", "tar", "pickle", "pkl"
        ])
        let fileExtension = (artifact.path as NSString).pathExtension.lowercased()
        guard !forbiddenExtensions.contains(fileExtension) else {
            throw LocalModelCatalogError.forbiddenArtifact(artifact.path)
        }
    }

    private static func validate(url: URL, approvedOrigins: Set<String>) throws {
        guard url.scheme == "https",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              let host = url.host?.lowercased(),
              approvedOrigins.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
        else {
            throw LocalModelCatalogError.unsupportedURL(url.absoluteString)
        }
    }

    private static func isSafeSingleComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
            && !value.contains("\\") && !value.contains("\0")
    }

    private static func isLowercaseHex(_ value: String, count: Int) -> Bool {
        value.utf8.count == count
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
            }
    }

    private static func isConservativeIdentifier(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122)
                    || $0 == 45 || $0 == 46 || $0 == 95
            }
    }

    private static func semanticVersion(_ value: String) -> [Int]? {
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(components.count) else { return nil }
        var version = components.compactMap { component -> Int? in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let number = Int(component)
            else {
                return nil
            }
            return number
        }
        guard version.count == components.count else { return nil }
        version.append(contentsOf: repeatElement(0, count: 4 - version.count))
        return version
    }
}
