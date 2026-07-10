import Foundation
import OSLog

public actor LocalModelManager: LocalModelManaging {
    private static let logger = Logger(
        subsystem: "media.luxel.app",
        category: "model-management"
    )

    private struct SchedulerWaiter {
        let id: LocalModelID
        let continuation: CheckedContinuation<Void, Never>
    }

    private let descriptorsByID: [LocalModelID: LocalModelDescriptor]
    private let validators: [LocalModelValidatorKey: any LocalModelValidating]
    private let downloader: any LocalModelDownloading
    private let verifier: any LocalModelArtifactVerifying
    private let repository: any LocalModelRepository
    private var states: [LocalModelID: LocalModelInstallationState] = [:]
    private var generation: UInt64 = 0
    private var observers: [UUID: AsyncStream<LocalModelStateChange>.Continuation] = [:]
    private var installTasks: [LocalModelID: Task<LocalModelInstallation, any Error>] = [:]
    private var activeSchedulerID: LocalModelID?
    private var schedulerWaiters: [SchedulerWaiter] = []
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

private extension LocalModelManager {
    private func performInstall(_ id: LocalModelID) async throws -> LocalModelInstallation {
        let priorState = states[id]
        var enteredInstallation = false
        do {
            try await waitForScheduler(id)
            try Task.checkCancellation()
            enteredInstallation = true
            let installation = try await runInstallation(id)
            finishScheduler(id)
            return installation
        } catch {
            finishScheduler(id)
            let failure = Self.mapFailure(error)
            if !enteredInstallation, failure == .canceled,
               let priorState {
                publish(priorState, for: id)
            }
            throw failure
        }
    }

    private func runInstallation(_ id: LocalModelID) async throws -> LocalModelInstallation {
        guard let descriptor = descriptorsByID[id],
              let validator = validators[descriptor.currentRelease.validatorKey]
        else {
            throw LocalModelFailure.invalidCatalog("No compatible validator is registered")
        }
        let priorReady = states[id]?.installation
        if let priorReady, priorReady.commit == descriptor.currentRelease.commit,
           case .ready = state(for: id) {
            return priorReady
        }

        let availableCapacity = try repository.availableCapacity()
        guard availableCapacity >= descriptor.currentRelease.requiredFreeBytes else {
            let failure = LocalModelFailure.insufficientDiskSpace(
                required: descriptor.currentRelease.requiredFreeBytes,
                available: availableCapacity
            )
            publish(.failed(failure, priorReadyInstallation: priorReady), for: id)
            throw failure
        }

        let staging = try repository.beginStaging(for: id)
        do {
            try await downloadAndVerifyArtifacts(
                descriptor: descriptor,
                staging: staging,
                id: id
            )
            try repository.validateExactSourceFiles(
                release: descriptor.currentRelease,
                staging: staging
            )
            let installation = try await prepareAndPromote(
                descriptor: descriptor,
                staging: staging,
                validator: validator,
                id: id
            )
            publish(.ready(installation), for: id)
            return installation
        } catch {
            repository.discard(staging)
            let failure = Self.mapFailure(error)
            if failure == .canceled {
                let stableState =
                    priorReady.map { installation -> LocalModelInstallationState in
                        if installation.commit == descriptor.currentRelease.commit {
                            return .ready(installation)
                        }
                        return .updateAvailable(
                            installed: installation,
                            available: descriptor.currentRelease
                        )
                    } ?? Self.notInstalledState(for: descriptor)
                publish(stableState, for: id)
            } else {
                publish(.failed(failure, priorReadyInstallation: priorReady), for: id)
            }
            throw failure
        }
    }

    private func downloadAndVerifyArtifacts(
        descriptor: LocalModelDescriptor,
        staging: LocalModelStagingArea,
        id: LocalModelID
    ) async throws {
        var verifiedBytes: Int64 = 0
        for artifact in descriptor.currentRelease.artifacts.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let destination = try repository.artifactURL(artifact, in: staging)
            let previouslyVerifiedBytes = verifiedBytes
            try await downloader.download(
                LocalModelArtifactDownloadRequest(
                    provider: descriptor.currentRelease.provider,
                    repository: descriptor.currentRelease.repository,
                    commit: descriptor.currentRelease.commit,
                    artifact: artifact,
                    destinationURL: destination
                )
            ) { [weak self] receivedBytes in
                await self?.publishDownloadProgress(
                    for: id,
                    verifiedBytes: previouslyVerifiedBytes,
                    receivedBytes: receivedBytes,
                    totalBytes: descriptor.currentRelease.expectedPayloadBytes,
                    artifact: artifact.path
                )
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: destination.path
            )
            publish(
                .verifying(
                    LocalModelProgress(
                        phase: .verifying,
                        completedBytes: verifiedBytes,
                        totalBytes: descriptor.currentRelease.expectedPayloadBytes,
                        currentArtifact: artifact.path
                    )
                ),
                for: id
            )
            try verifier.verify(fileAt: destination, artifact: artifact)
            verifiedBytes += artifact.byteCount
        }
    }

    private func prepareAndPromote(
        descriptor: LocalModelDescriptor,
        staging: LocalModelStagingArea,
        validator: any LocalModelValidating,
        id: LocalModelID
    ) async throws -> LocalModelInstallation {
        publish(
            .preparing(
                LocalModelProgress(
                    phase: .preparing,
                    completedBytes: descriptor.currentRelease.expectedPayloadBytes,
                    totalBytes: descriptor.currentRelease.expectedPayloadBytes
                )
            ),
            for: id
        )
        await Task.yield()
        publish(.validating, for: id)
        let prepared = try await validator.prepareAndValidate(
            release: descriptor.currentRelease,
            stagedPayload: staging.sourceRoot,
            preparedOutput: staging.preparedRoot
        )
        try Task.checkCancellation()
        return try repository.promote(
            descriptor: descriptor,
            staging: staging,
            prepared: prepared,
            validatorVersion: validator.version
        )
    }

    private func waitForScheduler(_ id: LocalModelID) async throws {
        if activeSchedulerID == nil {
            activeSchedulerID = id
            return
        }
        publish(.queued(position: schedulerWaiters.count + 1), for: id)
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                schedulerWaiters.append(SchedulerWaiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelSchedulerWaiter(id) }
        }
        try Task.checkCancellation()
    }

    private func cancelSchedulerWaiter(_ id: LocalModelID) {
        guard let index = schedulerWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = schedulerWaiters.remove(at: index)
        waiter.continuation.resume()
        refreshQueuePositions()
    }

    private func finishScheduler(_ id: LocalModelID) {
        guard activeSchedulerID == id else {
            return
        }
        if schedulerWaiters.isEmpty {
            activeSchedulerID = nil
            return
        }
        let next = schedulerWaiters.removeFirst()
        activeSchedulerID = next.id
        next.continuation.resume()
        refreshQueuePositions()
    }

    private func refreshQueuePositions() {
        for (index, waiter) in schedulerWaiters.enumerated() {
            publish(.queued(position: index + 1), for: waiter.id)
        }
    }

    private func publishDownloadProgress(
        for id: LocalModelID,
        verifiedBytes: Int64,
        receivedBytes: Int64,
        totalBytes: Int64,
        artifact: String
    ) {
        let priorCompleted: Int64
        if case .downloading(let progress) = states[id] {
            priorCompleted = progress.completedBytes
        } else {
            priorCompleted = 0
        }
        publish(
            .downloading(
                LocalModelProgress(
                    phase: .downloading,
                    completedBytes: max(priorCompleted, verifiedBytes + receivedBytes),
                    totalBytes: totalBytes,
                    currentArtifact: artifact
                )
            ),
            for: id
        )
    }

    private func publish(_ state: LocalModelInstallationState, for id: LocalModelID) {
        states[id] = state
        generation &+= 1
        let diagnostic =
            "model=\(id.rawValue) state=\(state.diagnosticCategory) generation=\(generation)"
        Self.logger.info("\(diagnostic, privacy: .public)")
        let change = LocalModelStateChange(modelID: id, state: state, generation: generation)
        for continuation in observers.values {
            continuation.yield(change)
        }
    }

    private func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private static func notInstalledState(
        for descriptor: LocalModelDescriptor
    ) -> LocalModelInstallationState {
        .notInstalled(
            expectedDownloadBytes: descriptor.currentRelease.expectedPayloadBytes,
            requiredFreeBytes: descriptor.currentRelease.requiredFreeBytes
        )
    }

    private static func mapFailure(_ error: any Error) -> LocalModelFailure {
        if error is CancellationError {
            return .canceled
        }
        if let failure = error as? LocalModelFailure {
            return failure
        }
        if let urlError = error as? URLError,
           urlError.code == .notConnectedToInternet {
            return .networkUnavailable
        }
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: cocoaError.code) {
            case .fileWriteNoPermission, .fileReadNoPermission:
                return .storagePermission
            case .fileWriteOutOfSpace:
                return .storageFailure("The disk became full while installing the model")
            case .fileWriteUnknown, .fileWriteVolumeReadOnly, .fileWriteFileExists,
                 .fileWriteInvalidFileName:
                return .storageFailure("The model could not be written to disk")
            default:
                break
            }
        }
        return .validationFailed(String(reflecting: type(of: error)))
    }
}

extension LocalModelInstallationState {
    fileprivate var diagnosticCategory: String {
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

    fileprivate var installation: LocalModelInstallation? {
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

    fileprivate var isStableInstalledState: Bool {
        switch self {
        case .ready, .updateAvailable:
            true
        default:
            false
        }
    }
}

extension LocalModelFailure {
    fileprivate var diagnosticCategory: String {
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
