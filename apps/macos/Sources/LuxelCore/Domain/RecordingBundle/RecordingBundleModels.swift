import Foundation

public enum SidecarKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case camera
    case cursor
    case keystrokes
    case captions

    public var defaultFileName: String {
        switch self {
        case .camera:
            "camera.mov"
        case .cursor:
            "cursor.json"
        case .keystrokes:
            "keystrokes.json"
        case .captions:
            "captions.json"
        }
    }
}

public struct BundleSidecarManifest: Codable, Equatable, Sendable {
    public let kind: SidecarKind
    public let fileName: String
    public let syncOffsetMilliseconds: Int?

    public init(
        kind: SidecarKind,
        fileName: String? = nil,
        syncOffsetMilliseconds: Int? = nil
    ) throws {
        let resolvedFileName = fileName ?? kind.defaultFileName
        try BundleManifest.validateBundleFileName(resolvedFileName)

        self.kind = kind
        self.fileName = resolvedFileName
        self.syncOffsetMilliseconds = syncOffsetMilliseconds
    }
}

public struct BundleManifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultPrimaryFileName = "screen.mov"
    public static let fileName = "bundle.json"

    public let schemaVersion: Int
    public let primaryFileName: String
    public let sidecars: [BundleSidecarManifest]

    public init(
        schemaVersion: Int = BundleManifest.currentSchemaVersion,
        primaryFileName: String = BundleManifest.defaultPrimaryFileName,
        sidecars: [BundleSidecarManifest] = []
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RecordingBundleError.unsupportedSchemaVersion
        }

        try Self.validateBundleFileName(primaryFileName)
        try Self.validateSidecars(sidecars, primaryFileName: primaryFileName)

        self.schemaVersion = schemaVersion
        self.primaryFileName = primaryFileName
        self.sidecars = sidecars
    }

    public func sidecar(for kind: SidecarKind) -> BundleSidecarManifest? {
        sidecars.first { $0.kind == kind }
    }

    public func filteringSidecars(
        _ isIncluded: (BundleSidecarManifest) -> Bool
    ) throws -> BundleManifest {
        try BundleManifest(
            schemaVersion: schemaVersion,
            primaryFileName: primaryFileName,
            sidecars: sidecars.filter(isIncluded)
        )
    }

    static func validateBundleFileName(_ fileName: String) throws {
        guard !fileName.isEmpty,
            !fileName.contains("/"),
            fileName != ".",
            fileName != ".."
        else {
            throw RecordingBundleError.invalidBundleFileName
        }
    }

    private static func validateSidecars(
        _ sidecars: [BundleSidecarManifest],
        primaryFileName: String
    ) throws {
        var seenKinds: Set<SidecarKind> = []
        var seenFileNames: Set<String> = [primaryFileName]

        for sidecar in sidecars {
            guard seenKinds.insert(sidecar.kind).inserted else {
                throw RecordingBundleError.duplicateSidecarKind
            }

            guard seenFileNames.insert(sidecar.fileName).inserted else {
                throw RecordingBundleError.duplicateBundleFileName
            }
        }
    }
}

public struct RecordingBundle: Equatable, Sendable {
    public let rootURL: URL
    public let manifest: BundleManifest

    public init(rootURL: URL, manifest: BundleManifest) {
        self.rootURL = rootURL
        self.manifest = manifest
    }

    public var primaryURL: URL {
        rootURL.appendingPathComponent(manifest.primaryFileName)
    }

    public var manifestURL: URL {
        rootURL.appendingPathComponent(BundleManifest.fileName)
    }

    public var sidecars: [SidecarKind: URL] {
        Dictionary(
            uniqueKeysWithValues: manifest.sidecars.map { sidecar in
                (sidecar.kind, rootURL.appendingPathComponent(sidecar.fileName))
            })
    }

    public func sidecarURL(for kind: SidecarKind) -> URL? {
        guard let sidecar = manifest.sidecar(for: kind) else {
            return nil
        }

        return rootURL.appendingPathComponent(sidecar.fileName)
    }
}

public enum RecordingBundleError: Error, Equatable {
    case unsupportedSchemaVersion
    case invalidBundleFileName
    case duplicateSidecarKind
    case duplicateBundleFileName
}
