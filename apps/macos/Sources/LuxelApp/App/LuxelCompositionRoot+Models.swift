import Foundation
import LuxelCore

extension LuxelCompositionRoot {
    static let localModelManager: any LocalModelManaging = {
        FluidAudioOfflinePolicy.enable()
        let validator = ParakeetPrecisionModelValidator()
        do {
            let catalog = try BundledLocalModelCatalog.production(
                registeredValidatorKeys: [validator.key],
                attributionIdentifiers: [
                    "fluidinference-parakeet-tdt-0.6b-v3-coreml"
                ],
                currentAppVersion: appMetadata.version
            )
            let metadata = appMetadata
            return try LocalModelManager(
                catalogProvider: catalog,
                validators: [validator],
                downloader: HuggingFaceModelArtifactDownloadClient(
                    userAgent: "Luxel/\(metadata.version)"
                ),
                verifier: SHA256ArtifactVerifier(),
                repository: ApplicationSupportLocalModelRepository(
                    root: downloadedModelsDirectory,
                    appVersion: metadata.version,
                    appBuild: metadata.build
                )
            )
        } catch {
            return UnavailableLocalModelManager()
        }
    }()

    static let precisionTranscriptionEngine = PrecisionTranscriptionEngine(
        modelManager: localModelManager
    )

    static func precisionTranscriptionCoordinator() -> PrecisionTranscriptionCoordinator {
        PrecisionTranscriptionCoordinator(
            settingsStore: settingsStore(),
            modelManager: localModelManager,
            engine: precisionTranscriptionEngine
        )
    }

    static func selectedTranscriptionProvenanceResolver(
        settingsStore: any SettingsStore
    ) -> SelectedTranscriptionProvenanceResolver {
        SelectedTranscriptionProvenanceResolver(
            settingsStore: settingsStore,
            modelManager: localModelManager
        )
    }

    static func captionTranscriptionService() -> TranscribeRecordingService {
        let settingsStore = settingsStore()
        let resolver = selectedTranscriptionProvenanceResolver(settingsStore: settingsStore)
        return TranscribeRecordingService(
            transcriber: SelectedEngineCaptionSpeechTranscriber(
                precision: PrecisionCaptionSpeechTranscriber(
                    engine: precisionTranscriptionEngine
                ),
                provenance: { try await resolver.resolve() }
            ),
            sidecarPersistence: CaptionSidecarPersistenceService(
                fileSystem: LocalFileSystem()
            )
        )
    }

    static var downloadedModelsDirectory: URL {
        applicationSupportDirectory
            .appending(path: "Luxel", directoryHint: .isDirectory)
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "Downloaded", directoryHint: .isDirectory)
    }
}

private actor UnavailableLocalModelManager: LocalModelManaging {
    func descriptors() -> [LocalModelDescriptor] { [] }

    func state(for id: LocalModelID) -> LocalModelInstallationState {
        .failed(
            .invalidCatalog("The bundled model catalog is unavailable"),
            priorReadyInstallation: nil
        )
    }

    func stateChanges() -> AsyncStream<LocalModelStateChange> {
        AsyncStream { $0.finish() }
    }

    func install(_ id: LocalModelID) async throws -> LocalModelInstallation {
        throw LocalModelFailure.invalidCatalog("The bundled model catalog is unavailable")
    }

    func cancelInstallation(_ id: LocalModelID) {}
    func remove(_ id: LocalModelID) async throws {}

    func acquire(_ id: LocalModelID) async throws -> LocalModelLease {
        throw LocalModelFailure.notInstalled
    }

    func release(_ lease: LocalModelLease) {}
    func reportInvalid(_ lease: LocalModelLease, reason: LocalModelRuntimeInvalidation) {}
}
