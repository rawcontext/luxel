import Foundation

public struct SelectedTranscriptionProvenanceResolver: Sendable {
    private let settingsStore: any SettingsStore
    private let modelManager: any LocalModelManaging

    public init(
        settingsStore: any SettingsStore,
        modelManager: any LocalModelManaging
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
    }

    public func resolve() async throws -> TranscriptionProvenance {
        let settings = try settingsStore.load()
        guard settings.transcriptEnginePreference == .precision else {
            return .appleSpeech
        }
        let state = await modelManager.state(for: PrecisionTranscriptionEngine.modelID)
        let installation: LocalModelInstallation
        switch state {
        case .ready(let ready), .updateAvailable(let ready, _):
            installation = ready
        case .failed(_, let priorReadyInstallation?):
            installation = priorReadyInstallation
        case .repairRequired:
            throw PrecisionTranscriptionError.modelCorrupt
        default:
            throw PrecisionTranscriptionError.modelNotInstalled
        }
        return TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: installation.commit,
            configurationRevision: PrecisionTranscriptionEngine.configurationRevision
        )
    }
}

public actor PrecisionTranscriptionCoordinator {
    private let settingsStore: any SettingsStore
    private let modelManager: any LocalModelManaging
    private let engine: PrecisionTranscriptionEngine

    public init(
        settingsStore: any SettingsStore,
        modelManager: any LocalModelManaging,
        engine: PrecisionTranscriptionEngine
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.engine = engine
    }

    @discardableResult
    public func installAndEnable(locale: Locale) async throws -> LocalModelInstallation {
        _ = try PrecisionTranscriptionLanguageCatalog.languageCode(for: locale)
        let installation = try await modelManager.install(PrecisionTranscriptionEngine.modelID)
        let lease = try await modelManager.acquire(PrecisionTranscriptionEngine.modelID)
        await modelManager.release(lease)
        var settings = try settingsStore.load()
        settings.transcriptEnginePreference = .precision
        try settingsStore.save(settings)
        return installation
    }

    public func enable(locale: Locale) async throws {
        _ = try PrecisionTranscriptionLanguageCatalog.languageCode(for: locale)
        let lease = try await modelManager.acquire(PrecisionTranscriptionEngine.modelID)
        await modelManager.release(lease)
        var settings = try settingsStore.load()
        settings.transcriptEnginePreference = .precision
        try settingsStore.save(settings)
    }

    public func disable() throws {
        var settings = try settingsStore.load()
        settings.transcriptEnginePreference = .appleSpeech
        try settingsStore.save(settings)
    }

    public func remove() async throws {
        try disable()
        await engine.unload()
        try await modelManager.remove(PrecisionTranscriptionEngine.modelID)
    }

    public func reconcilePreference() async throws {
        var settings = try settingsStore.load()
        guard settings.transcriptEnginePreference == .precision else {
            return
        }
        let state = await modelManager.state(for: PrecisionTranscriptionEngine.modelID)
        switch state {
        case .ready, .updateAvailable, .failed(_, priorReadyInstallation: .some):
            return
        default:
            settings.transcriptEnginePreference = .appleSpeech
            try settingsStore.save(settings)
        }
    }
}
