import Foundation
import Testing

@testable import LuxelCore

// MARK: - Profile store

@Suite("Known speaker profile store")
struct FileKnownSpeakerProfileStoreTests {
    private struct StoredLibraryDocument: Codable {
        let schemaVersion: Int
        let profiles: [KnownSpeakerProfile]
    }

    private func makeStore() throws -> (FileKnownSpeakerProfileStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelKnownSpeakerTests-\(UUID().uuidString)")
        return (FileKnownSpeakerProfileStore(directory: directory), directory)
    }

    private func sampleProfile(named name: String = "Sarah Chen") throws -> KnownSpeakerProfile {
        try KnownSpeakerProfile(
            displayName: name,
            embeddings: [
                try SpeakerEmbedding(
                    vector: [0.1, 0.2, 0.3],
                    modelIdentifier: "model-a",
                    backend: .fluidAudioWeSpeaker
                )
            ]
        )
    }

    private func writeStoredProfiles(
        _ profiles: [KnownSpeakerProfile],
        to directory: URL
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            StoredLibraryDocument(
                schemaVersion: FileKnownSpeakerProfileStore.schemaVersion,
                profiles: profiles
            )
        ).write(to: directory.appending(path: "known-speakers.json"))
    }

    private func storedProfiles(in directory: URL) throws -> [KnownSpeakerProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            StoredLibraryDocument.self,
            from: Data(contentsOf: directory.appending(path: "known-speakers.json"))
        ).profiles
    }

    @Test("saves loads renames and deletes profiles with revision updates")
    func savesLoadsRenamesDeletes() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = try store.library()
        #expect(empty.profiles.isEmpty)

        var profile = try sampleProfile()
        let afterSave = try store.save(profile)
        #expect(afterSave.profiles.map(\.displayName) == ["Sarah Chen"])
        #expect(afterSave.revision != empty.revision)

        profile.displayName = "Sarah C."
        let afterRename = try store.save(profile)
        #expect(afterRename.profiles.map(\.displayName) == ["Sarah C."])
        #expect(afterRename.revision != afterSave.revision)

        let reloaded = try store.library()
        #expect(reloaded.profiles.map(\.id) == afterRename.profiles.map(\.id))
        #expect(reloaded.profiles.map(\.displayName) == ["Sarah C."])
        #expect(reloaded.revision == afterRename.revision)

        let afterDelete = try store.deleteProfile(id: profile.id)
        #expect(afterDelete.profiles.isEmpty)
        #expect(throws: KnownSpeakerError.profileNotFound(profile.id)) {
            try store.deleteProfile(id: profile.id)
        }
    }

    @Test("stores model and backend identity with every embedding")
    func storesModelIdentityWithEmbeddings() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.save(try sampleProfile())
        let embedding = try #require(try store.library().profiles.first?.embeddings.first)

        #expect(embedding.modelIdentifier == "model-a")
        #expect(embedding.backend == .fluidAudioWeSpeaker)
    }

    @Test("metadata-only updates keep the library revision stable")
    func metadataUpdatesKeepRevisionStable() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        var profile = try sampleProfile()
        let initial = try store.save(profile)

        profile.matchedRecordingCount = 5
        profile.lastMatchedAt = Date()
        let afterMetadata = try store.save(profile)

        #expect(afterMetadata.revision == initial.revision)
    }

    @Test("migrates duplicate names without losing speaker data or double-counting recordings")
    func migratesDuplicateNames() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingURL = URL(fileURLWithPath: "/tmp/shared-recording.m4a")
        let firstClip = try KnownSpeakerExampleClip(
            audioURL: directory.appending(path: "first.m4a"),
            duration: 3,
            sourceRecordingURL: recordingURL
        )
        let duplicateClip = try KnownSpeakerExampleClip(
            audioURL: directory.appending(path: "duplicate.m4a"),
            duration: 4,
            sourceRecordingURL: recordingURL
        )
        let firstCreatedAt = Date(timeIntervalSince1970: 100)
        let duplicateUpdatedAt = Date(timeIntervalSince1970: 300)
        var first = try sampleProfile(named: "Jordan Smith")
        first.exampleClips = [firstClip]
        first.matchedRecordingCount = 2
        first.lastMatchedAt = Date(timeIntervalSince1970: 200)
        first.createdAt = firstCreatedAt
        first.updatedAt = Date(timeIntervalSince1970: 200)
        var duplicate = try sampleProfile(named: "  JORDAN   SMITH  ")
        duplicate.exampleClips = [duplicateClip]
        duplicate.matchedRecordingCount = 1
        duplicate.lastMatchedAt = duplicateUpdatedAt
        duplicate.createdAt = Date(timeIntervalSince1970: 250)
        duplicate.updatedAt = duplicateUpdatedAt
        try writeStoredProfiles([first, duplicate], to: directory)

        let migrated = try store.library()
        let profile = try #require(migrated.profiles.first)
        #expect(migrated.profiles.count == 1)
        #expect(profile.id == first.id)
        #expect(profile.displayName == "Jordan Smith")
        #expect(
            Set(profile.embeddings.map(\.id))
                == [first.embeddings[0].id, duplicate.embeddings[0].id]
        )
        #expect(Set(profile.exampleClips.map(\.id)) == [firstClip.id, duplicateClip.id])
        #expect(profile.matchedRecordingCount == 2)
        #expect(profile.lastMatchedAt == duplicateUpdatedAt)
        #expect(profile.createdAt == firstCreatedAt)
        #expect(profile.updatedAt == duplicateUpdatedAt)

        #expect(try storedProfiles(in: directory) == migrated.profiles)
    }

    @Test("imports example clips into library-owned storage")
    func importsExampleClips() throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "LuxelClipSource-\(UUID().uuidString).m4a")
        try Data([0x01, 0x02, 0x03]).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let clip = try store.importExampleClip(
            from: sourceURL,
            duration: 4.2,
            sourceRecordingURL: nil
        )

        #expect(clip.audioURL.path.hasPrefix(directory.path))
        #expect(FileManager.default.fileExists(atPath: clip.audioURL.path))
        #expect(clip.duration == 4.2)

        try store.removeExampleClipFile(clip)
        #expect(!FileManager.default.fileExists(atPath: clip.audioURL.path))
    }
}
