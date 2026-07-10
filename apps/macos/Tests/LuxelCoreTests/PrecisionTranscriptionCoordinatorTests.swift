import Foundation
import LuxelCore
import Testing

@Suite("Precision transcription coordinator")
struct PrecisionTranscriptionCoordinatorTests {
    @Test("successful validated install activates Precision transactionally")
    func successfulInstallActivatesPrecision() async throws {
        let installation = precisionFixtureInstallation()
        let manager = CoordinatorModelManager(installation: installation)
        let store = CoordinatorSettingsStore(settings: fixtureSettings())
        let coordinator = PrecisionTranscriptionCoordinator(
            settingsStore: store,
            modelManager: manager,
            engine: PrecisionTranscriptionEngine(modelManager: manager)
        )

        let installed = try await coordinator.installAndEnable(
            locale: Locale(identifier: "en-US")
        )

        #expect(installed == installation)
        #expect(try store.load().transcriptEnginePreference == .precision)
        #expect(await manager.installCount == 1)
        #expect(await manager.acquireCount == 1)
    }

    @Test("install or settings persistence failure leaves Apple Speech active")
    func failureLeavesAppleSpeechActive() async throws {
        let failedManager = CoordinatorModelManager(
            installation: precisionFixtureInstallation(),
            installFailure: .checksumMismatch
        )
        let firstStore = CoordinatorSettingsStore(settings: fixtureSettings())
        let failedCoordinator = PrecisionTranscriptionCoordinator(
            settingsStore: firstStore,
            modelManager: failedManager,
            engine: PrecisionTranscriptionEngine(modelManager: failedManager)
        )
        await #expect(throws: LocalModelFailure.checksumMismatch) {
            try await failedCoordinator.installAndEnable(locale: Locale(identifier: "en-US"))
        }
        #expect(try firstStore.load().transcriptEnginePreference == .appleSpeech)

        let readyManager = CoordinatorModelManager(
            installation: precisionFixtureInstallation()
        )
        let rejectingStore = CoordinatorSettingsStore(
            settings: fixtureSettings(),
            rejectsSaves: true
        )
        let rejectingCoordinator = PrecisionTranscriptionCoordinator(
            settingsStore: rejectingStore,
            modelManager: readyManager,
            engine: PrecisionTranscriptionEngine(modelManager: readyManager)
        )
        await #expect(throws: CoordinatorSettingsError.saveRejected) {
            try await rejectingCoordinator.installAndEnable(locale: Locale(identifier: "en-US"))
        }
        #expect(try rejectingStore.load().transcriptEnginePreference == .appleSpeech)
    }

    @Test("stale preference is reconciled and removal switches engines first")
    func stalePreferenceAndRemovalAreSafe() async throws {
        var staleSettings = fixtureSettings()
        staleSettings.transcriptEnginePreference = .precision
        let missingManager = CoordinatorModelManager(installation: nil)
        let staleStore = CoordinatorSettingsStore(settings: staleSettings)
        let staleCoordinator = PrecisionTranscriptionCoordinator(
            settingsStore: staleStore,
            modelManager: missingManager,
            engine: PrecisionTranscriptionEngine(modelManager: missingManager)
        )

        try await staleCoordinator.reconcilePreference()
        #expect(try staleStore.load().transcriptEnginePreference == .appleSpeech)

        let readyManager = CoordinatorModelManager(
            installation: precisionFixtureInstallation()
        )
        var enabledSettings = fixtureSettings()
        enabledSettings.transcriptEnginePreference = .precision
        let enabledStore = CoordinatorSettingsStore(settings: enabledSettings)
        let coordinator = PrecisionTranscriptionCoordinator(
            settingsStore: enabledStore,
            modelManager: readyManager,
            engine: PrecisionTranscriptionEngine(modelManager: readyManager)
        )

        try await coordinator.remove()
        #expect(try enabledStore.load().transcriptEnginePreference == .appleSpeech)
        #expect(await readyManager.removeCount == 1)
    }
}

private enum CoordinatorSettingsError: Error {
    case saveRejected
}

private final class CoordinatorSettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings
    private let rejectsSaves: Bool

    init(settings: AppSettings, rejectsSaves: Bool = false) {
        self.settings = settings
        self.rejectsSaves = rejectsSaves
    }

    func load() throws -> AppSettings {
        lock.withLock { settings }
    }

    func save(_ settings: AppSettings) throws {
        if rejectsSaves { throw CoordinatorSettingsError.saveRejected }
        lock.withLock { self.settings = settings }
    }
}

private actor CoordinatorModelManager: LocalModelManaging {
    private var installation: LocalModelInstallation?
    private let installFailure: LocalModelFailure?
    private(set) var installCount = 0
    private(set) var acquireCount = 0
    private(set) var removeCount = 0

    init(
        installation: LocalModelInstallation?,
        installFailure: LocalModelFailure? = nil
    ) {
        self.installation = installation
        self.installFailure = installFailure
    }

    func descriptors() -> [LocalModelDescriptor] { [] }

    func state(for id: LocalModelID) -> LocalModelInstallationState {
        installation.map(LocalModelInstallationState.ready)
            ?? .notInstalled(expectedDownloadBytes: 483_105_645, requiredFreeBytes: 1_050_000_000)
    }

    func stateChanges() -> AsyncStream<LocalModelStateChange> {
        AsyncStream { $0.finish() }
    }

    func install(_ id: LocalModelID) throws -> LocalModelInstallation {
        installCount += 1
        if let installFailure { throw installFailure }
        guard let installation else { throw LocalModelFailure.notInstalled }
        return installation
    }

    func cancelInstallation(_ id: LocalModelID) {}

    func remove(_ id: LocalModelID) throws {
        removeCount += 1
        installation = nil
    }

    func acquire(_ id: LocalModelID) throws -> LocalModelLease {
        acquireCount += 1
        guard let installation else { throw LocalModelFailure.notInstalled }
        return LocalModelLease(
            token: UUID(),
            modelID: id,
            commit: installation.commit,
            payloadRoot: installation.payloadRoot,
            validatorKey: installation.validatorKey
        )
    }

    func release(_ lease: LocalModelLease) {}
    func reportInvalid(_ lease: LocalModelLease, reason: LocalModelRuntimeInvalidation) {}
}

private func fixtureSettings() -> AppSettings {
    AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/LuxelTests"))
}

private func precisionFixtureInstallation() -> LocalModelInstallation {
    LocalModelInstallation(
        modelID: PrecisionTranscriptionEngine.modelID,
        commit: String(repeating: "a", count: 40),
        engineRevision: PrecisionTranscriptionEngine.configurationRevision,
        payloadRoot: URL(fileURLWithPath: "/tmp/LuxelPrecisionFixture"),
        logicalBytes: 483_105_645,
        allocatedBytes: 483_106_816,
        validatorKey: ParakeetPrecisionModelValidator.validatorKey,
        validatorVersion: 1,
        installedAt: Date(timeIntervalSince1970: 0)
    )
}
