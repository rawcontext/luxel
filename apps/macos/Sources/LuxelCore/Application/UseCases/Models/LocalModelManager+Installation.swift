import Foundation

extension LocalModelManager {
    func performInstall(_ id: LocalModelID) async throws -> LocalModelInstallation {
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

        try validateAvailableCapacity(for: descriptor, priorReady: priorReady, id: id)

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

    private func validateAvailableCapacity(
        for descriptor: LocalModelDescriptor,
        priorReady: LocalModelInstallation?,
        id: LocalModelID
    ) throws {
        let availableCapacity = try repository.availableCapacity()
        guard availableCapacity >= descriptor.currentRelease.requiredFreeBytes else {
            let failure = LocalModelFailure.insufficientDiskSpace(
                required: descriptor.currentRelease.requiredFreeBytes,
                available: availableCapacity
            )
            publish(.failed(failure, priorReadyInstallation: priorReady), for: id)
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

    func cancelSchedulerWaiter(_ id: LocalModelID) {
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

    func publish(_ state: LocalModelInstallationState, for id: LocalModelID) {
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

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    static func notInstalledState(
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
