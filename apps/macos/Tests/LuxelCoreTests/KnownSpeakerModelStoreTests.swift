import Foundation
import Testing

@testable import LuxelCore

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
        let fixture = try bundledStoreFixture(prefix: "LuxelBundledModelTests")
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let state = try await fixture.store.prepareModel()

        guard case .ready(let installedBytes, let revision) = state else {
            Issue.record("Expected ready state, got \(state)")
            return
        }

        #expect(installedBytes > 0)
        #expect(revision == FluidAudioSpeakerDiarizationModelStore.modelRevision)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.modelsDirectory
                    .appending(path: "speaker-diarization/Segmentation.mlmodelc/model.mil").path))

        // Removal frees the disk copy; the next prepare re-seeds from the bundle.
        try await fixture.store.removeModel()
        #expect(!(await fixture.store.currentState().isReady))
        let reseeded = try await fixture.store.prepareModel()
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
        #expect(
            SpeakerModelCatalog.speakerDiarization.revision
                == FluidAudioSpeakerDiarizationModelStore.modelSourceRevision)
        #expect(SpeakerModelCatalog.speakerDiarization.expectedDownloadBytes == 21_776_918)
        #expect(FluidAudioSpeakerDiarizer.offlineClusteringThreshold == 0.6)
    }

    @Test("matching marker without audited artifacts is not ready")
    func matchingMarkerWithoutAuditedArtifactsIsNotReady() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload = Data(repeating: 0xAB, count: 4096)
        try payload.write(to: directory.appending(path: "model.mlmodelc"))
        try writeRuntimeManifest(
            at: directory,
            packageVersion: "0.15.6",
            revision: FluidAudioSpeakerDiarizationModelStore.modelRevision,
            expectedBytes: 21_776_918
        )

        #expect(
            await store.currentState()
                == .notDownloaded(
                    expectedBytes: SpeakerModelCatalog.speakerDiarization.expectedDownloadBytes
                )
        )
    }

    @Test("prepare repairs a corrupt installed artifact from the bundle")
    func prepareRepairsCorruptInstalledArtifactFromBundle() async throws {
        let fixture = try bundledStoreFixture(prefix: "LuxelSpeakerModelRepairTests")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        _ = try await fixture.store.prepareModel()

        let relativeWeight = "speaker-diarization/Embedding.mlmodelc/weights/weight.bin"
        let installedWeight = fixture.modelsDirectory.appending(path: relativeWeight)
        var corruptData = try Data(contentsOf: installedWeight)
        corruptData.append(Data("tamper".utf8))
        try corruptData.write(to: installedWeight)

        #expect(!(await fixture.store.currentState().isReady))
        #expect(try await fixture.store.prepareModel().isReady)
        #expect(
            try Data(contentsOf: installedWeight)
                == Data(
                    contentsOf: fixture.bundled
                        .appending(path: "Embedding.mlmodelc/weights/weight.bin")
                )
        )
    }

    private func bundledStoreFixture(prefix: String) throws -> BundledSpeakerStoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "\(prefix)-\(UUID().uuidString)")
        let bundled = try sharedPackageRootURL()
            .appending(path: "Vendor/Models/speaker-diarization")
        let modelsDirectory = root.appending(path: "installed")
        return BundledSpeakerStoreFixture(
            root: root,
            bundled: bundled,
            modelsDirectory: modelsDirectory,
            store: FluidAudioSpeakerDiarizationModelStore(
                modelsDirectory: modelsDirectory,
                bundledModelDirectory: bundled
            )
        )
    }

    private func writeRuntimeManifest(
        at directory: URL,
        packageVersion: String,
        revision: String,
        expectedBytes: Int64
    ) throws {
        let manifest = """
        {
          "packageVersion": "\(packageVersion)",
          "repository": "FluidInference/speaker-diarization-coreml",
          "revision": "\(revision)",
          "expectedBytes": \(expectedBytes),
          "installedBytes": 4096,
          "installDate": 773190000.0,
          "licenseIdentifier": "cc-by-4.0"
        }
        """
        try Data(manifest.utf8).write(
            to: directory.appending(path: "luxel-model-manifest.json")
        )
    }

    @Test("stale runtime manifest requires a fresh bundled seed")
    func staleManifestRequiresFreshSeed() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeRuntimeManifest(
            at: directory,
            packageVersion: "0.15.5",
            revision: "speaker-diarization-coreml@old",
            expectedBytes: 21_600_000
        )

        #expect(
            await store.currentState()
                == .notDownloaded(
                    expectedBytes: SpeakerModelCatalog.speakerDiarization.expectedDownloadBytes
                )
        )
    }

    @Test("remove model returns the store to not downloaded")
    func removeModelReturnsToNotDownloaded() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: directory.appending(path: "model.bin"))
        let manifest = """
        {
          "packageVersion": "0.15.6",
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

private struct BundledSpeakerStoreFixture {
    let root: URL
    let bundled: URL
    let modelsDirectory: URL
    let store: FluidAudioSpeakerDiarizationModelStore
}

@Suite("Bundled speaker diarization", .serialized)
struct BundledSpeakerDiarizationTests {
    @Test("configuration uses fixed Euclidean threshold semantics")
    func configurationUsesEuclideanThreshold() {
        let automatic = FluidAudioSpeakerDiarizer.offlineDiarizerConfig(
            speakerCountHint: .automatic
        )
        let exact = FluidAudioSpeakerDiarizer.offlineDiarizerConfig(
            speakerCountHint: .exact(1)
        )

        #expect(automatic.clusteringThreshold == 0.6)
        #expect(exact.clusteringThreshold == 0.6)
        #expect(exact.clustering.numSpeakers == 1)
    }

    @Test("missing bundled models fail closed without downloading")
    func missingModelsFailClosed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelMissingSpeakerModels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        await #expect(throws: (any Error).self) {
            _ = try await FluidAudioSpeakerDiarizer.loadModelsOffline(from: directory)
        }

        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
        #expect(files.allSatisfy { !$0.hasSuffix(".mlmodelc") })
    }

    @Test("real bundled pipeline diarizes licensed speech locally")
    func realBundledPipelineDiarizesSpeech() async throws {
        let root = packageRootURL()
        let diarizer = FluidAudioSpeakerDiarizer(
            modelsDirectory: root.appending(path: "Vendor/Models", directoryHint: .isDirectory)
        )
        let speechURL = root.appending(
            path: "Tests/LuxelCoreTests/Fixtures/VoiceDetection/speech-16k-mono.wav"
        )

        let output = try await diarizer.diarize(SpeakerDiarizationRequest(
            audioURL: speechURL,
            modelRevision: FluidAudioSpeakerDiarizationModelStore.modelRevision
        ))

        #expect(!output.segments.isEmpty)
        #expect(Set(output.segments.map(\.speakerID)) == ["speaker-0"])
        #expect(output.segments.allSatisfy { $0.start >= 0 && $0.end > $0.start })
        #expect(output.segments == output.segments.sorted { $0.start < $1.start })
    }

    private func packageRootURL() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            url.deleteLastPathComponent()
        }
        return url.deletingLastPathComponent()
    }
}
