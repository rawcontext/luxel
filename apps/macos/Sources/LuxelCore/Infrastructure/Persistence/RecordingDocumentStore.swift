import Foundation

public struct RecordingDocumentStore: Sendable {
    static let documentLock = NSRecursiveLock()
    private static let sourceLocations = RecordingSourceLocations()
    public init() {}

    public func load(nextTo mediaURL: URL) throws -> RecordingBundle? {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        let mediaURL = Self.currentMediaURL(for: mediaURL)
        let root = mediaURL.deletingLastPathComponent()
        let manifestURL = root.appending(path: BundleManifest.fileName)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest = try JSONDecoder().decode(BundleManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.organization != nil, manifest.primaryFileName == mediaURL.lastPathComponent else {
            return nil
        }
        let validated = try BundleManifest(
            schemaVersion: manifest.schemaVersion, primaryFileName: manifest.primaryFileName,
            sidecars: manifest.sidecars, organization: manifest.organization
        )
        if let name = validated.organization?.transcriptFileName {
            try BundleManifest.validateBundleFileName(name)
        }
        guard validated.organization?.exports.allSatisfy({ Self.isSafeRelativePath($0.relativePath) }) == true else {
            throw RecordingBundleError.invalidBundleFileName
        }
        return RecordingBundle(rootURL: root, manifest: validated)
    }

    public func save(_ manifest: BundleManifest, in root: URL) throws {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: root.appending(path: BundleManifest.fileName), options: .atomic)
    }

    public func create(
        for recording: PastRecording, captureKind: String, sourceApplication: String? = nil
    ) throws -> PastRecording {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        let sourceURL = recording.primaryMediaURL
        if let existing = try load(nextTo: sourceURL) {
            return recording.replacingBundleManifest(existing.manifest)
        }
        let root = sourceURL.deletingLastPathComponent()
        guard root.lastPathComponent == sourceURL.deletingPathExtension().lastPathComponent else {
            return recording
        }
        var sidecars: [BundleSidecarManifest] = []
        if let url = KeystrokeSidecarFileLoader().sidecarURL(nextTo: sourceURL) {
            sidecars.append(try BundleSidecarManifest(kind: .keystrokes, fileName: url.lastPathComponent))
        }
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let title = stem.components(separatedBy: " - ").dropFirst().joined(separator: " - ")
        var organization = RecordingOrganization(
            capturedAt: recording.date, captureKind: captureKind,
            sourceApplication: sourceApplication, title: title.isEmpty ? stem : title
        )
        organization.recordingOptions = recording.options
        let manifest = try BundleManifest(
            primaryFileName: sourceURL.lastPathComponent, sidecars: sidecars, organization: organization)
        try save(manifest, in: root)
        return recording.replacingFileURL(sourceURL, name: stem, bundleManifest: manifest)
    }

    @discardableResult
    public func update(
        nextTo mediaURL: URL, _ operation: (inout RecordingOrganization) -> Void
    ) throws -> BundleManifest? {
        Self.documentLock.lock()
        defer { Self.documentLock.unlock() }
        guard let bundle = try load(nextTo: mediaURL), var organization = bundle.manifest.organization else {
            return nil
        }
        operation(&organization)
        var manifest = bundle.manifest
        manifest.organization = organization
        try save(manifest, in: bundle.rootURL)
        return manifest
    }

    public func lockPaths(nextTo mediaURL: URL) throws {
        _ = try update(nextTo: mediaURL) { $0.pathsLocked = true }
    }

    public static func identifier(for mediaURL: URL) -> UUID? {
        (try? Self().load(nextTo: mediaURL))?.manifest.organization?.id
    }

    public static func currentMediaURL(for url: URL) -> URL {
        documentLock.lock()
        defer { documentLock.unlock() }
        let key = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let current = sourceLocations.files[key] { return current }
        for (root, current) in sourceLocations.directories {
            if key == root { return current }
            if key.hasPrefix(root + "/") {
                return current.appending(path: String(key.dropFirst(root.count + 1)))
            }
        }
        return url
    }

    static func recordMove(from oldURL: URL, to newURL: URL) {
        let old = oldURL.standardizedFileURL.resolvingSymlinksInPath().path
        let new = newURL.standardizedFileURL
        for key in Array(sourceLocations.files.keys)
        where sourceLocations.files[key]?.resolvingSymlinksInPath().path == old {
            sourceLocations.files[key] = new
        }
        sourceLocations.files.removeValue(forKey: new.resolvingSymlinksInPath().path)
        sourceLocations.files[old] = new
        let oldRoot = oldURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let newRoot = new.deletingLastPathComponent()
        if oldRoot != newRoot.resolvingSymlinksInPath().path { sourceLocations.directories[oldRoot] = newRoot }
    }

    public static func setTitlePending(_ pending: Bool, id: UUID) {
        documentLock.lock()
        defer { documentLock.unlock() }
        if pending { sourceLocations.pendingTitles.insert(id) } else { sourceLocations.pendingTitles.remove(id) }
    }

    public static func isTitlePending(for mediaURL: URL) -> Bool {
        documentLock.lock()
        defer { documentLock.unlock() }
        guard let id = identifier(for: mediaURL) else { return false }
        return sourceLocations.pendingTitles.contains(id)
    }

    public static func exportsDirectory(for mediaURL: URL) -> URL? {
        guard let bundle = try? Self().load(nextTo: mediaURL) else { return nil }
        return bundle.rootURL.appending(path: "Exports", directoryHint: .isDirectory)
    }

    public func recordExport(_ export: RecordingExport, sourceURL: URL) throws {
        let root = sourceURL.deletingLastPathComponent().standardizedFileURL.path + "/"
        let path = export.fileURL.standardizedFileURL.path
        _ = try update(nextTo: sourceURL) { organization in
            organization.pathsLocked = true
            guard path.hasPrefix(root) else { return }
            let relative = String(path.dropFirst(root.count))
            organization.exports.removeAll { $0.relativePath == relative }
            organization.exports.append(
                RecordingExportReference(
                    relativePath: relative, format: export.format, date: export.date, presetName: export.presetName))
        }
    }

    public func recordings(in root: URL) -> [PastRecording] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        var recordings: [PastRecording] = []
        for case let url as URL in enumerator where url.lastPathComponent == BundleManifest.fileName {
            guard let data = try? Data(contentsOf: url),
                let manifest = try? JSONDecoder().decode(BundleManifest.self, from: data),
                let organization = manifest.organization,
                (try? BundleManifest.validateBundleFileName(manifest.primaryFileName)) != nil,
                let bundle = try? load(
                    nextTo: url.deletingLastPathComponent().appending(path: manifest.primaryFileName)),
                FileManager.default.fileExists(atPath: bundle.primaryURL.path)
            else { continue }
            let exports = organization.exports.map {
                RecordingExport(
                    fileURL: bundle.rootURL.appending(path: $0.relativePath),
                    format: $0.format, date: $0.date, presetName: $0.presetName)
            }
            recordings.append(
                PastRecording(
                    fileURL: bundle.primaryURL, name: bundle.primaryURL.deletingPathExtension().lastPathComponent,
                    date: organization.capturedAt,
                    options: organization.recordingOptions
                        ?? RecordingOptions(frameRate: 0, isAudioOnly: organization.captureKind == "audio"),
                    exports: exports, bundleManifest: bundle.manifest
                ))
        }
        return recordings
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\")
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }
}

private final class RecordingSourceLocations: @unchecked Sendable {
    var files: [String: URL] = [:]
    var directories: [String: URL] = [:]
    var pendingTitles: Set<UUID> = []
}
