import Foundation

/// Stores the known-speaker library as JSON under
/// `Application Support/Luxel/Known Speakers`, with example clips copied into a
/// `Clips` subdirectory. Everything stays local; nothing is synced or uploaded.
public final class FileKnownSpeakerProfileStore: KnownSpeakerProfileStore, @unchecked Sendable {
    public static let schemaVersion = 1

    private let directory: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func library() throws -> KnownSpeakerLibrary {
        lock.lock()
        defer { lock.unlock() }
        let profiles = try loadProfiles()
        return KnownSpeakerLibrary(profiles: profiles, revision: Self.revision(for: profiles))
    }

    @discardableResult
    public func save(_ profile: KnownSpeakerProfile) throws -> KnownSpeakerLibrary {
        lock.lock()
        defer { lock.unlock() }
        var profiles = try loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles = Self.mergingDuplicateProfiles(profiles)

        try writeProfiles(profiles)
        return KnownSpeakerLibrary(profiles: profiles, revision: Self.revision(for: profiles))
    }

    @discardableResult
    public func deleteProfile(id: UUID) throws -> KnownSpeakerLibrary {
        lock.lock()
        defer { lock.unlock() }
        var profiles = try loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw KnownSpeakerError.profileNotFound(id)
        }

        let removed = profiles.remove(at: index)
        try writeProfiles(profiles)
        for clip in removed.exampleClips {
            try? fileManager.removeItem(at: clip.audioURL)
        }

        return KnownSpeakerLibrary(profiles: profiles, revision: Self.revision(for: profiles))
    }

    public func importExampleClip(
        from audioURL: URL,
        duration: TimeInterval,
        sourceRecordingURL: URL?
    ) throws -> KnownSpeakerExampleClip {
        lock.lock()
        defer { lock.unlock() }
        let clipID = UUID()
        let storedURL = clipsDirectory.appending(
            path:
                "\(clipID.uuidString).\(audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension)"
        )
        try fileManager.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: audioURL, to: storedURL)
        return try KnownSpeakerExampleClip(
            id: clipID,
            audioURL: storedURL,
            duration: duration,
            sourceRecordingURL: sourceRecordingURL
        )
    }

    public func removeExampleClipFile(_ clip: KnownSpeakerExampleClip) throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: clip.audioURL.path) {
            try fileManager.removeItem(at: clip.audioURL)
        }
    }

    private var libraryURL: URL {
        directory.appending(path: "known-speakers.json")
    }

    private var clipsDirectory: URL {
        directory.appending(path: "Clips")
    }

    private func loadProfiles() throws -> [KnownSpeakerProfile] {
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return []
        }

        let document = try decoder.decode(
            LibraryDocument.self,
            from: Data(contentsOf: libraryURL)
        )
        guard document.schemaVersion == Self.schemaVersion else {
            throw TranscriptModelError.unsupportedCacheSchemaVersion(document.schemaVersion)
        }

        let profiles = Self.mergingDuplicateProfiles(document.profiles)
        if profiles != document.profiles {
            try writeProfiles(profiles)
        }
        return profiles
    }

    private func writeProfiles(_ profiles: [KnownSpeakerProfile]) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let document = LibraryDocument(schemaVersion: Self.schemaVersion, profiles: profiles)
        try encoder.encode(document).write(to: libraryURL, options: .atomic)
    }

    /// Content-derived revision: changes only when identity-relevant data
    /// (names, embeddings, clips) changes, so match-count metadata updates do
    /// not invalidate cached transcripts.
    static func revision(for profiles: [KnownSpeakerProfile]) -> String {
        let identity =
            profiles
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { profile in
                let embeddingIDs = profile.embeddings.map(\.id.uuidString).sorted()
                    .joined(separator: ",")
                let clipIDs = profile.exampleClips.map(\.id.uuidString).sorted()
                    .joined(separator: ",")
                return "\(profile.id.uuidString)|\(profile.displayName)|\(embeddingIDs)|\(clipIDs)"
            }
            .joined(separator: ";")

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return String(hash, radix: 16)
    }

    private static func mergingDuplicateProfiles(
        _ profiles: [KnownSpeakerProfile]
    ) -> [KnownSpeakerProfile] {
        var merged: [KnownSpeakerProfile] = []
        var indexByName: [String: Int] = [:]

        for profile in profiles {
            let name = normalizedName(profile.displayName)
            guard let existingIndex = indexByName[name] else {
                indexByName[name] = merged.count
                merged.append(profile)
                continue
            }

            merged[existingIndex] = merging(merged[existingIndex], with: profile)
        }

        return merged
    }

    private static func normalizedName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private static func merging(
        _ canonical: KnownSpeakerProfile,
        with duplicate: KnownSpeakerProfile
    ) -> KnownSpeakerProfile {
        var profile = canonical
        let canonicalRecordings = sourceRecordings(for: canonical)
        let duplicateRecordings = sourceRecordings(for: duplicate)
        let untrackedCanonicalMatches =
            canonical.matchedRecordingCount - canonicalRecordings.count
        let untrackedDuplicateMatches =
            duplicate.matchedRecordingCount - duplicateRecordings.count

        var embeddingIDs = Set(profile.embeddings.map(\.id))
        profile.embeddings.append(
            contentsOf: duplicate.embeddings.filter {
                embeddingIDs.insert($0.id).inserted
            })
        var clipIDs = Set(profile.exampleClips.map(\.id))
        profile.exampleClips.append(
            contentsOf: duplicate.exampleClips.filter {
                clipIDs.insert($0.id).inserted
            })
        profile.matchedRecordingCount =
            canonicalRecordings.union(duplicateRecordings).count
            + untrackedCanonicalMatches
            + untrackedDuplicateMatches
        profile.lastMatchedAt = [canonical.lastMatchedAt, duplicate.lastMatchedAt]
            .compactMap { $0 }
            .max()
        profile.createdAt = min(canonical.createdAt, duplicate.createdAt)
        profile.updatedAt = max(canonical.updatedAt, duplicate.updatedAt)
        return profile
    }

    private static func sourceRecordings(for profile: KnownSpeakerProfile) -> Set<URL> {
        Set(profile.exampleClips.compactMap(\.sourceRecordingURL))
    }
}

private struct LibraryDocument: Codable {
    let schemaVersion: Int
    let profiles: [KnownSpeakerProfile]
}
