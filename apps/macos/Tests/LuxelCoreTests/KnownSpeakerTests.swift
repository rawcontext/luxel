import Foundation
import Testing

@testable import LuxelCore

// MARK: - Matcher

@Suite("Known speaker matcher")
struct KnownSpeakerMatcherTests {
    private let modelIdentifier = "speaker-diarization-coreml@fluidaudio-test"

    private func profile(
        named name: String,
        vector: [Float],
        backend: SpeakerEmbeddingBackend = .fluidAudioWeSpeaker,
        modelIdentifier: String? = nil
    ) throws -> KnownSpeakerProfile {
        try KnownSpeakerProfile(
            displayName: name,
            embeddings: [
                try SpeakerEmbedding(
                    vector: vector,
                    modelIdentifier: modelIdentifier ?? self.modelIdentifier,
                    backend: backend
                )
            ]
        )
    }

    @Test("matches only compatible embedding backends and model identity")
    func matchesOnlyCompatibleBackends() throws {
        let vector: [Float] = [1, 0, 0]
        let incompatibleBackend = try profile(
            named: "Wrong Backend", vector: vector, backend: .fluidAudioCampPlus)
        let incompatibleModel = try profile(
            named: "Wrong Model", vector: vector, modelIdentifier: "other-model")
        let matcher = KnownSpeakerMatcher(modelIdentifier: modelIdentifier)

        let matches = matcher.matches(
            for: ["speaker-0": vector],
            library: KnownSpeakerLibrary(
                profiles: [incompatibleBackend, incompatibleModel],
                revision: "1"
            )
        )

        #expect(matches.isEmpty)
    }

    @Test("requires minimum similarity and second-best margin")
    func requiresMinimumSimilarityAndMargin() throws {
        let matcher = KnownSpeakerMatcher(
            configuration: KnownSpeakerMatcherConfiguration(
                minimumSimilarity: 0.8,
                minimumSecondBestMargin: 0.15
            ),
            modelIdentifier: modelIdentifier
        )
        let target = try profile(named: "Target", vector: [1, 0, 0])
        let nearTwin = try profile(named: "Near Twin", vector: [0.95, 0.3122499, 0])

        // Below the similarity floor: stays anonymous.
        let weak = matcher.matches(
            for: ["speaker-0": [0, 1, 0]],
            library: KnownSpeakerLibrary(profiles: [target], revision: "1")
        )
        #expect(weak.isEmpty)

        // Strong best match but runner-up within the margin: stays anonymous.
        let ambiguous = matcher.matches(
            for: ["speaker-0": [1, 0.05, 0]],
            library: KnownSpeakerLibrary(profiles: [target, nearTwin], revision: "1")
        )
        #expect(ambiguous.isEmpty)

        // Strong and unambiguous: matched.
        let confident = matcher.matches(
            for: ["speaker-0": [1, 0, 0]],
            library: KnownSpeakerLibrary(profiles: [target], revision: "1")
        )
        #expect(confident["speaker-0"]?.displayName == "Target")
    }

    @Test("resolves conflicts globally when two voices claim one profile")
    func resolvesConflictsGlobally() throws {
        let matcher = KnownSpeakerMatcher(
            configuration: KnownSpeakerMatcherConfiguration(
                minimumSimilarity: 0.5,
                minimumSecondBestMargin: 0
            ),
            modelIdentifier: modelIdentifier
        )
        let profile = try profile(named: "Contested", vector: [1, 0, 0])

        let matches = matcher.matches(
            for: [
                "speaker-0": [1, 0, 0],
                "speaker-1": [0.9, 0.4358899, 0]
            ],
            library: KnownSpeakerLibrary(profiles: [profile], revision: "1")
        )

        #expect(matches.count == 1)
        #expect(matches["speaker-0"]?.displayName == "Contested")
        #expect(matches["speaker-1"] == nil)
    }

    @Test("cosine similarity handles identical orthogonal and invalid vectors")
    func cosineSimilarityBehaves() {
        #expect(abs(KnownSpeakerMatcher.cosineSimilarity([1, 0], [1, 0]) - 1) < 0.0001)
        #expect(abs(KnownSpeakerMatcher.cosineSimilarity([1, 0], [0, 1])) < 0.0001)
        #expect(KnownSpeakerMatcher.cosineSimilarity([1, 0], [1, 0, 0]) == -1)
        #expect(KnownSpeakerMatcher.cosineSimilarity([], []) == -1)
        #expect(KnownSpeakerMatcher.cosineSimilarity([0, 0], [1, 0]) == -1)
    }

    @Test("rejects malformed embedding vectors")
    func rejectsMalformedEmbeddings() {
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [],
                modelIdentifier: "model",
                backend: .fluidAudioWeSpeaker
            )
        }
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [1, .nan],
                modelIdentifier: "model",
                backend: .fluidAudioWeSpeaker
            )
        }
        #expect(throws: KnownSpeakerError.invalidEmbedding) {
            _ = try SpeakerEmbedding(
                vector: [1, 2],
                modelIdentifier: "",
                backend: .fluidAudioWeSpeaker
            )
        }
    }
}

// MARK: - Profile store

@Suite("Known speaker profile store")
struct FileKnownSpeakerProfileStoreTests {
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

// MARK: - Model store

@Suite("Speaker diarization model store")
struct SpeakerDiarizationModelStoreTests {
    private func makeStore() -> (FluidAudioSpeakerDiarizationModelStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelSpeakerModelTests-\(UUID().uuidString)")
        return (FluidAudioSpeakerDiarizationModelStore(modelsDirectory: directory), directory)
    }

    @Test("prepare seeds from a bundled model copy without downloading")
    func prepareSeedsFromBundledCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "LuxelBundledModelTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundled = root.appending(path: "bundle/speaker-diarization")
        try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 2048).write(to: bundled.appending(path: "model.bin"))
        let modelsDirectory = root.appending(path: "installed")
        let store = FluidAudioSpeakerDiarizationModelStore(
            modelsDirectory: modelsDirectory,
            bundledModelDirectory: bundled
        )

        let state = try await store.prepareModel()

        guard case .ready(let installedBytes, let revision) = state else {
            Issue.record("Expected ready state, got \(state)")
            return
        }

        #expect(installedBytes > 0)
        #expect(revision == FluidAudioSpeakerDiarizationModelStore.modelRevision)
        #expect(
            FileManager.default.fileExists(
                atPath: modelsDirectory.appending(path: "speaker-diarization/model.bin").path))

        // Removal frees the disk copy; the next prepare re-seeds from the bundle.
        try await store.removeModel()
        #expect(!(await store.currentState().isReady))
        let reseeded = try await store.prepareModel()
        #expect(reseeded.isReady)
    }

    @Test("reports not downloaded with catalog size before install")
    func reportsNotDownloadedBeforeInstall() async {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let state = await store.currentState()
        #expect(
            state
                == .notDownloaded(
                    expectedBytes: SpeakerModelCatalog.speakerDiarization.expectedDownloadBytes))

        let info = await store.modelInfo()
        #expect(info.repository == "FluidInference/speaker-diarization-coreml")
        #expect(info.licenseIdentifier == "cc-by-4.0")
        #expect(info.revision == FluidAudioSpeakerDiarizationModelStore.modelRevision)
    }

    @Test("reports ready with measured installed bytes when a manifest exists")
    func reportsReadyFromManifestAndMeasuresDisk() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data(repeating: 0xAB, count: 4096)
        try payload.write(to: directory.appending(path: "model.mlmodelc"))
        let manifest = """
        {
          "packageVersion": "0.15.5",
          "repository": "FluidInference/speaker-diarization-coreml",
          "revision": "test-revision",
          "expectedBytes": 129200000,
          "installedBytes": 4096,
          "installDate": 773190000.0,
          "licenseIdentifier": "cc-by-4.0"
        }
        """
        try Data(manifest.utf8).write(to: directory.appending(path: "luxel-model-manifest.json"))

        let state = await store.currentState()
        guard case .ready(let installedBytes, let revision) = state else {
            Issue.record("Expected ready state, got \(state)")
            return
        }

        #expect(installedBytes > 0)
        #expect(revision == "test-revision")

        let info = await store.modelInfo()
        #expect(info.revision == "test-revision")
    }

    @Test("remove model returns the store to not downloaded")
    func removeModelReturnsToNotDownloaded() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appending(path: "model.bin"))
        let manifest = """
        {
          "packageVersion": "0.15.5",
          "repository": "FluidInference/speaker-diarization-coreml",
          "revision": "test-revision",
          "installedBytes": 1,
          "installDate": 773190000.0
        }
        """
        try Data(manifest.utf8).write(to: directory.appending(path: "luxel-model-manifest.json"))

        try await store.removeModel()

        let state = await store.currentState()
        #expect(
            state
                == .notDownloaded(
                    expectedBytes: SpeakerModelCatalog.speakerDiarization.expectedDownloadBytes))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
