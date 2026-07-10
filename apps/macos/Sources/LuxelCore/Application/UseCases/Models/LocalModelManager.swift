import Foundation
import OSLog

public actor LocalModelManager: LocalModelManaging {
    static let logger = Logger(
        subsystem: "media.luxel.app",
        category: "model-management"
    )

    struct SchedulerWaiter {
        let id: LocalModelID
        let continuation: CheckedContinuation<Void, Never>
    }

    let descriptorsByID: [LocalModelID: LocalModelDescriptor]
    let validators: [LocalModelValidatorKey: any LocalModelValidating]
    let downloader: any LocalModelDownloading
    let verifier: any LocalModelArtifactVerifying
    let repository: any LocalModelRepository
    var states: [LocalModelID: LocalModelInstallationState] = [:]
    var generation: UInt64 = 0
    var observers: [UUID: AsyncStream<LocalModelStateChange>.Continuation] = [:]
    private var installTasks: [LocalModelID: Task<LocalModelInstallation, any Error>] = [:]
    var activeSchedulerID: LocalModelID?
    var schedulerWaiters: [SchedulerWaiter] = []
    private var leases: [UUID: LocalModelLease] = [:]

    public init(
        catalogProvider: any LocalModelCatalogProviding,
        validators: [any LocalModelValidating],
        downloader: any LocalModelDownloading,
        verifier: any LocalModelArtifactVerifying,
        repository: any LocalModelRepository
    ) throws {
        let catalog = try catalogProvider.catalog()
        let validatorsByKey = Dictionary(uniqueKeysWithValues: validators.map { ($0.key, $0) })
        self.descriptorsByID = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0) })
        self.validators = validatorsByKey
        self.downloader = downloader
        self.verifier = verifier
        self.repository = repository

        for descriptor in catalog.models {
            guard let validator = validatorsByKey[descriptor.currentRelease.validatorKey],
                  validator.version >= descriptor.currentRelease.minimumValidatorVersion
            else {
                states[descriptor.id] = .failed(
                    .invalidCatalog("No compatible validator is registered"),
                    priorReadyInstallation: nil
                )
                continue
            }
            do {
                if let installation = try repository.reconcile(
                    descriptor: descriptor,
                    validatorVersion: validator.version
                ) {
                    states[descriptor.id] =
                        installation.commit == descriptor.currentRelease.commit
                        ? .ready(installation)
                        : .updateAvailable(
                            installed: installation,
                            available: descriptor.currentRelease
                        )
                } else {
                    states[descriptor.id] = Self.notInstalledState(for: descriptor)
                }
            } catch let failure as LocalModelFailure {
                states[descriptor.id] = .repairRequired(nil, failure)
            } catch {
                states[descriptor.id] = .repairRequired(
                    nil,
                    .installationCorrupt("Model installation could not be reconciled")
                )
            }
        }
    }

    public func descriptors() -> [LocalModelDescriptor] {
        descriptorsByID.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public func state(for id: LocalModelID) -> LocalModelInstallationState {
        guard let descriptor = descriptorsByID[id],
              let validator = validators[descriptor.currentRelease.validatorKey]
        else {
            return .failed(.invalidCatalog("Unknown model"), priorReadyInstallation: nil)
        }
        let existing = states[id] ?? Self.notInstalledState(for: descriptor)
        guard existing.isStableInstalledState else {
            return existing
        }

        do {
            guard
                let installation = try repository.reconcile(
                    descriptor: descriptor,
                    validatorVersion: validator.version
                )
            else {
                let failure = LocalModelFailure.installationCorrupt("Installed model is missing")
                publish(.repairRequired(existing.installation, failure), for: id)
                return states[id]!
            }
            let refreshed: LocalModelInstallationState =
                installation.commit == descriptor.currentRelease.commit
                ? .ready(installation)
                : .updateAvailable(installed: installation, available: descriptor.currentRelease)
            states[id] = refreshed
            return refreshed
        } catch let failure as LocalModelFailure {
            let repair = LocalModelInstallationState.repairRequired(existing.installation, failure)
            publish(repair, for: id)
            return repair
        } catch {
            let repair = LocalModelInstallationState.repairRequired(
                existing.installation,
                .installationCorrupt("Installed model files changed")
            )
            publish(repair, for: id)
            return repair
        }
    }

    public func stateChanges() -> AsyncStream<LocalModelStateChange> {
        let observerID = UUID()
        return AsyncStream { continuation in
            observers[observerID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    public func install(_ id: LocalModelID) async throws -> LocalModelInstallation {
        guard descriptorsByID[id] != nil else {
            throw LocalModelFailure.invalidCatalog("Unknown model")
        }
        if let task = installTasks[id] {
            return try await task.value
        }

        let task = Task { try await self.performInstall(id) }
        installTasks[id] = task
        do {
            let installation = try await task.value
            installTasks[id] = nil
            return installation
        } catch {
            installTasks[id] = nil
            throw error
        }
    }

    public func cancelInstallation(_ id: LocalModelID) {
        guard let task = installTasks[id] else {
            return
        }
        publish(.canceling, for: id)
        task.cancel()
        cancelSchedulerWaiter(id)
    }

    public func remove(_ id: LocalModelID) async throws {
        guard let descriptor = descriptorsByID[id] else {
            throw LocalModelFailure.invalidCatalog("Unknown model")
        }
        guard !leases.values.contains(where: { $0.modelID == id }) else {
            throw LocalModelFailure.inUse
        }
        guard installTasks[id] == nil else {
            throw LocalModelFailure.inUse
        }
        let currentState = state(for: id)
        guard let installation = currentState.installation else {
            if case .notInstalled = currentState {
                return
            }
            throw LocalModelFailure.notInstalled
        }

        publish(.removing, for: id)
        do {
            try repository.remove(installation)
            publish(Self.notInstalledState(for: descriptor), for: id)
        } catch let failure as LocalModelFailure {
            publish(.failed(failure, priorReadyInstallation: installation), for: id)
            throw failure
        }
    }

    public func acquire(_ id: LocalModelID) async throws -> LocalModelLease {
        let current = state(for: id)
        let installation: LocalModelInstallation
        switch current {
        case .ready(let ready), .updateAvailable(let ready, _):
            installation = ready
        case .failed(_, let priorReadyInstallation?):
            guard let descriptor = descriptorsByID[id],
                  let validator = validators[descriptor.currentRelease.validatorKey],
                  let reconciled = try repository.reconcile(
                    descriptor: descriptor,
                    validatorVersion: validator.version
                  ),
                  reconciled.commit == priorReadyInstallation.commit
            else {
                let failure = LocalModelFailure.installationCorrupt(
                    "The previous model release is no longer valid"
                )
                publish(.repairRequired(priorReadyInstallation, failure), for: id)
                throw failure
            }
            installation = reconciled
        case .repairRequired:
            throw LocalModelFailure.installationCorrupt("Model requires repair")
        default:
            throw LocalModelFailure.notInstalled
        }
        let lease = LocalModelLease(
            token: UUID(),
            modelID: id,
            commit: installation.commit,
            payloadRoot: installation.payloadRoot,
            validatorKey: installation.validatorKey
        )
        leases[lease.token] = lease
        return lease
    }

    public func release(_ lease: LocalModelLease) {
        leases.removeValue(forKey: lease.token)
    }

    public func reportInvalid(
        _ lease: LocalModelLease,
        reason: LocalModelRuntimeInvalidation
    ) {
        guard leases[lease.token] == lease else {
            return
        }
        let installation = states[lease.modelID]?.installation
        publish(
            .repairRequired(
                installation,
                .installationCorrupt("Runtime validation failed: \(reason)")
            ),
            for: lease.modelID
        )
    }
}

extension LocalModelInstallationState {
    var diagnosticCategory: String {
        switch self {
        case .notInstalled: "not-installed"
        case .queued: "queued"
        case .downloading: "downloading"
        case .verifying: "verifying"
        case .preparing: "preparing"
        case .validating: "validating"
        case .ready: "ready"
        case .updateAvailable: "update-available"
        case .repairRequired: "repair-required"
        case .canceling: "canceling"
        case .removing: "removing"
        case .failed(let failure, _): "failed-\(failure.diagnosticCategory)"
        }
    }

    var installation: LocalModelInstallation? {
        switch self {
        case .ready(let installation), .updateAvailable(let installation, _):
            installation
        case .repairRequired(let installation, _),
             .failed(_, let installation):
            installation
        default:
            nil
        }
    }

    var isStableInstalledState: Bool {
        switch self {
        case .ready, .updateAvailable:
            true
        default:
            false
        }
    }
}

extension LocalModelFailure {
    var diagnosticCategory: String {
        switch self {
        case .invalidCatalog: "invalid-catalog"
        case .unavailableInAppVersion: "incompatible-app"
        case .insufficientDiskSpace: "insufficient-space"
        case .networkUnavailable: "offline"
        case .transport: "transport"
        case .httpStatus: "http"
        case .rateLimited: "rate-limited"
        case .forbiddenRedirect: "forbidden-redirect"
        case .responseTooLarge: "oversized-response"
        case .unexpectedByteCount: "byte-count"
        case .checksumMismatch: "checksum"
        case .invalidFileType: "file-type"
        case .unexpectedFileSet: "file-set"
        case .storagePermission: "storage-permission"
        case .storageFailure: "storage"
        case .preparationFailed: "preparation"
        case .validationFailed: "validation"
        case .installationCorrupt: "corrupt"
        case .inUse: "in-use"
        case .canceled: "canceled"
        case .notInstalled: "not-installed"
        }
    }
}
