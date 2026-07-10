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
        #expect(FluidAudioSpeakerDiarizer.offlineClusteringThreshold == 0.7)
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
        #expect(revision == FluidAudioSpeakerDiarizationModelStore.modelRevision)

        let info = await store.modelInfo()
        #expect(info.revision == FluidAudioSpeakerDiarizationModelStore.modelRevision)
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
