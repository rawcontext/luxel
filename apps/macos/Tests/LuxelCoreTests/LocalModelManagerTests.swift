import CryptoKit
import Foundation
import LuxelCore
import Testing

@Suite("Downloaded model manager")
struct LocalModelManagerTests {
    @Test("fixture release installs, acquires, blocks removal while leased, and removes")
    func fixtureReleaseLifecycle() async throws {
        let fixture = try FixtureModelEnvironment()
        let installation = try await fixture.manager.install(fixture.id)

        #expect(installation.commit == fixture.descriptor.currentRelease.commit)
        #expect(installation.logicalBytes == 7)
        #expect(installation.allocatedBytes > 0)
        #expect(
            try fixture.root.resolvingSymlinksInPath()
                .resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        #expect(
            try installation.payloadRoot.deletingLastPathComponent()
                .resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup == true
        )
        let rootPermissions =
            try FileManager.default.attributesOfItem(
                atPath: fixture.root.resolvingSymlinksInPath().path
            )[.posixPermissions] as? NSNumber
        let artifactPermissions =
            try FileManager.default.attributesOfItem(
                atPath: installation.payloadRoot
                    .appending(path: "fixture-runtime/payload.bin").path
            )[.posixPermissions] as? NSNumber
        #expect(rootPermissions?.intValue == 0o700)
        #expect(artifactPermissions?.intValue == 0o600)
        #expect(
            FileManager.default.fileExists(
                atPath: installation.payloadRoot
                    .appending(path: "fixture-runtime/payload.bin").path
            )
        )
        guard case .ready(let ready) = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Expected ready state")
            return
        }
        #expect(ready.commit == installation.commit)

        let lease = try await fixture.manager.acquire(fixture.id)
        await #expect(throws: LocalModelFailure.inUse) {
            try await fixture.manager.remove(fixture.id)
        }
        await fixture.manager.release(lease)
        try await fixture.manager.remove(fixture.id)
        guard case .notInstalled = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Expected not installed state")
            return
        }
    }

    @Test("concurrent install callers share one artifact transfer")
    func concurrentInstallCallersCoalesce() async throws {
        let gate = DownloadGate()
        let fixture = try FixtureModelEnvironment(gate: gate)
        let first = Task { try await fixture.manager.install(fixture.id) }
        await gate.waitUntilStarted()
        let second = Task { try await fixture.manager.install(fixture.id) }
        await gate.open()

        let firstInstallation = try await first.value
        let secondInstallation = try await second.value
        #expect(firstInstallation == secondInstallation)
        #expect(await fixture.downloader.callCount() == 1)
    }

    @Test("observable phases are ordered and progress never moves backward")
    func stateStreamPublishesOrderedMonotonicProgress() async throws {
        let fixture = try FixtureModelEnvironment()
        let changes = await fixture.manager.stateChanges()
        let collector = Task { () -> [LocalModelInstallationState] in
            var states: [LocalModelInstallationState] = []
            for await change in changes where change.modelID == fixture.id {
                states.append(change.state)
                if case .ready = change.state { break }
            }
            return states
        }

        _ = try await fixture.manager.install(fixture.id)
        let states = await collector.value
        let phases = states.compactMap { state -> LocalModelPhase? in
            switch state {
            case .downloading(let progress), .verifying(let progress):
                progress.phase
            case .preparing:
                .preparing
            case .validating:
                .validating
            default:
                nil
            }
        }
        let completedBytes = states.compactMap { state -> Int64? in
            guard case .downloading(let progress) = state else { return nil }
            return progress.completedBytes
        }

        #expect(phases == [.downloading, .verifying, .preparing, .validating])
        #expect(completedBytes == completedBytes.sorted())
    }

    @Test("a queued model can be canceled without affecting the active install")
    func queuedCancellationIsIndependent() async throws {
        let gate = DownloadGate()
        let fixture = try FixtureModelEnvironment(gate: gate)
        let secondID = LocalModelID(rawValue: "fixture.second")!
        let secondDescriptor = LocalModelDescriptor(
            id: secondID,
            displayNameKey: "display",
            featureNameKey: "feature",
            summaryKey: "summary",
            downloadDisclosureKey: "download",
            removalWarningKey: "remove",
            category: "test",
            mayBeShared: false,
            licenseURL: fixture.descriptor.licenseURL,
            currentRelease: fixture.descriptor.currentRelease
        )
        let manager = try LocalModelManager(
            catalogProvider: FixtureCatalogProvider(
                descriptors: [fixture.descriptor, secondDescriptor]
            ),
            validators: [FixtureValidator(key: fixture.descriptor.currentRelease.validatorKey)],
            downloader: fixture.downloader,
            verifier: SHA256ArtifactVerifier(),
            repository: ApplicationSupportLocalModelRepository(
                root: fixture.root,
                appVersion: "1.0.0",
                appBuild: "1"
            )
        )
        let first = Task { try await manager.install(fixture.id) }
        await gate.waitUntilStarted()
        let second = Task { try await manager.install(secondID) }
        var becameQueued = false
        for _ in 0..<100 {
            if case .queued = await manager.state(for: secondID) {
                becameQueued = true
                break
            }
            await Task.yield()
        }
        #expect(becameQueued)

        await manager.cancelInstallation(secondID)
        await #expect(throws: LocalModelFailure.canceled) {
            try await second.value
        }
        guard case .notInstalled = await manager.state(for: secondID) else {
            Issue.record("Canceled queued model must return to not installed")
            return
        }

        await gate.open()
        _ = try await first.value
        #expect(await fixture.downloader.callCount() == 1)
    }

    @Test("cancellation removes staging and never creates ready state")
    func cancellationRemovesStaging() async throws {
        let gate = DownloadGate()
        let fixture = try FixtureModelEnvironment(gate: gate)
        let install = Task { try await fixture.manager.install(fixture.id) }
        await gate.waitUntilStarted()
        await fixture.manager.cancelInstallation(fixture.id)

        await #expect(throws: LocalModelFailure.canceled) {
            try await install.value
        }
        guard case .notInstalled = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Canceled install must return to not installed")
            return
        }
        let modelRoot = fixture.root.appending(path: fixture.id.rawValue)
        #expect(!FileManager.default.fileExists(atPath: modelRoot.appending(path: "staging").path))
        #expect(!FileManager.default.fileExists(atPath: modelRoot.appending(path: "releases").path))
    }

    @Test("checksum failure cannot promote a release")
    func checksumFailureCannotPromote() async throws {
        let fixture = try FixtureModelEnvironment(downloadedData: Data("wrong!!".utf8))
        await #expect(throws: LocalModelFailure.checksumMismatch) {
            try await fixture.manager.install(fixture.id)
        }
        guard
            case .failed(.checksumMismatch, priorReadyInstallation: nil) =
                await fixture.manager.state(for: fixture.id)
        else {
            Issue.record("Expected checksum failure state")
            return
        }
    }

    @Test("external deletion becomes repair required and never downloads implicitly")
    func externalDeletionBecomesRepairRequired() async throws {
        let fixture = try FixtureModelEnvironment()
        let installation = try await fixture.manager.install(fixture.id)
        try FileManager.default.removeItem(
            at: installation.payloadRoot.appending(path: "fixture-runtime/payload.bin")
        )

        guard case .repairRequired = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Expected repair-required state")
            return
        }
        #expect(await fixture.downloader.callCount() == 1)
    }

    @Test("symlinked and unexpected installed content is quarantined")
    func symlinkedInstalledContentIsQuarantined() async throws {
        let fixture = try FixtureModelEnvironment()
        let installation = try await fixture.manager.install(fixture.id)
        let unexpected = installation.payloadRoot
            .appending(path: "fixture-runtime")
            .appending(path: "unexpected.bin")
        try FileManager.default.createSymbolicLink(
            at: unexpected,
            withDestinationURL: URL(fileURLWithPath: "/dev/null")
        )

        guard case .repairRequired = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Symlinked installed content must require repair")
            return
        }
        #expect(await fixture.downloader.callCount() == 1)
    }

    @Test("runtime invalidation quarantines a ready installation")
    func runtimeInvalidationQuarantinesReadyInstallation() async throws {
        let fixture = try FixtureModelEnvironment()
        _ = try await fixture.manager.install(fixture.id)
        let lease = try await fixture.manager.acquire(fixture.id)
        await fixture.manager.reportInvalid(lease, reason: .loadFailed)
        guard case .repairRequired = await fixture.manager.state(for: fixture.id) else {
            Issue.record("Expected repair-required state")
            return
        }
        await #expect(throws: LocalModelFailure.self) {
            try await fixture.manager.acquire(fixture.id)
        }
        await fixture.manager.release(lease)
    }

    @Test("failed update keeps the previous ready revision leasable")
    func failedUpdatePreservesPreviousRelease() async throws {
        let fixture = try FixtureModelEnvironment()
        let previous = try await fixture.manager.install(fixture.id)
        let oldRelease = fixture.descriptor.currentRelease
        let newRelease = replacingReleaseIdentity(
            oldRelease,
            commit: String(repeating: "b", count: 40),
            engineRevision: "fixture-config-2"
        )
        let updatedDescriptor = LocalModelDescriptor(
            id: fixture.id,
            displayNameKey: fixture.descriptor.displayNameKey,
            featureNameKey: fixture.descriptor.featureNameKey,
            summaryKey: fixture.descriptor.summaryKey,
            downloadDisclosureKey: fixture.descriptor.downloadDisclosureKey,
            removalWarningKey: fixture.descriptor.removalWarningKey,
            category: fixture.descriptor.category,
            mayBeShared: fixture.descriptor.mayBeShared,
            licenseURL: fixture.descriptor.licenseURL,
            currentRelease: newRelease,
            previousRelease: oldRelease
        )
        let manager = try LocalModelManager(
            catalogProvider: FixtureCatalogProvider(descriptors: [updatedDescriptor]),
            validators: [FixtureValidator(key: oldRelease.validatorKey)],
            downloader: FixtureDownloader(data: Data("wrong!!".utf8), gate: nil),
            verifier: SHA256ArtifactVerifier(),
            repository: ApplicationSupportLocalModelRepository(
                root: fixture.root,
                appVersion: "1.0.0",
                appBuild: "2"
            )
        )

        guard case .updateAvailable(let installed, _) = await manager.state(for: fixture.id) else {
            Issue.record("Expected update available state")
            return
        }
        #expect(installed.commit == previous.commit)
        await #expect(throws: LocalModelFailure.checksumMismatch) {
            try await manager.install(fixture.id)
        }
        let lease = try await manager.acquire(fixture.id)
        #expect(lease.commit == previous.commit)
        await manager.release(lease)
        #expect(
            FileManager.default.fileExists(
                atPath: previous.payloadRoot.appending(path: "fixture-runtime/payload.bin").path
            )
        )
    }

    @Test("relaunch removes abandoned staging operations")
    func relaunchRemovesAbandonedStaging() async throws {
        let fixture = try FixtureModelEnvironment()
        let repository = ApplicationSupportLocalModelRepository(
            root: fixture.root,
            appVersion: "1.0.0",
            appBuild: "1"
        )
        let staging = try repository.beginStaging(for: fixture.id)
        try Data("partial".utf8).write(
            to: staging.sourceRoot.appending(path: "partial.bin")
        )

        let manager = try LocalModelManager(
            catalogProvider: FixtureCatalogProvider(descriptors: [fixture.descriptor]),
            validators: [FixtureValidator(key: fixture.descriptor.currentRelease.validatorKey)],
            downloader: fixture.downloader,
            verifier: SHA256ArtifactVerifier(),
            repository: repository
        )

        guard case .notInstalled = await manager.state(for: fixture.id) else {
            Issue.record("Abandoned first install must reconcile to not installed")
            return
        }
        #expect(!FileManager.default.fileExists(atPath: staging.sourceRoot.path))
        #expect(await fixture.downloader.callCount() == 0)
    }
}

private struct FixtureModelEnvironment {
    let id = LocalModelID(rawValue: "fixture.model")!
    let root: URL
    let descriptor: LocalModelDescriptor
    let downloader: FixtureDownloader
    let manager: LocalModelManager

    init(gate: DownloadGate? = nil, downloadedData: Data = Data("fixture".utf8)) throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "LuxelLocalModelTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let expectedData = Data("fixture".utf8)
        let artifact = LocalModelArtifact(
            path: "payload.bin",
            byteCount: Int64(expectedData.count),
            sha256: SHA256.hash(data: expectedData).map { String(format: "%02x", $0) }.joined(),
            kind: .auxiliaryData
        )
        let validatorKey = LocalModelValidatorKey(rawValue: "fixture")
        let release = LocalModelRelease(
            provider: .huggingFace,
            repository: "Fixture/model",
            commit: String(repeating: "a", count: 40),
            upstreamVersion: "fixture",
            engineRevision: "fixture-config-1",
            validatorKey: validatorKey,
            minimumValidatorVersion: 1,
            minimumAppVersion: "1.0.0",
            licenseIdentifier: "CC0-1.0",
            licenseDisplayName: "CC0",
            attributionIdentifier: "fixture",
            modelCardURL: URL(string: "https://huggingface.co/Fixture/model")!,
            expectedPayloadBytes: artifact.byteCount,
            requiredFreeBytes: artifact.byteCount,
            artifactCount: 1,
            artifacts: [artifact],
            runtimeDirectoryName: "fixture-runtime"
        )
        descriptor = LocalModelDescriptor(
            id: id,
            displayNameKey: "display",
            featureNameKey: "feature",
            summaryKey: "summary",
            downloadDisclosureKey: "download",
            removalWarningKey: "remove",
            category: "test",
            mayBeShared: false,
            licenseURL: URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")!,
            currentRelease: release
        )
        downloader = FixtureDownloader(data: downloadedData, gate: gate)
        manager = try LocalModelManager(
            catalogProvider: FixtureCatalogProvider(descriptor: descriptor),
            validators: [FixtureValidator(key: validatorKey)],
            downloader: downloader,
            verifier: SHA256ArtifactVerifier(),
            repository: ApplicationSupportLocalModelRepository(
                root: root,
                appVersion: "1.0.0",
                appBuild: "1"
            )
        )
    }
}

private struct FixtureCatalogProvider: LocalModelCatalogProviding {
    let descriptors: [LocalModelDescriptor]

    init(descriptor: LocalModelDescriptor) {
        descriptors = [descriptor]
    }

    init(descriptors: [LocalModelDescriptor]) {
        self.descriptors = descriptors
    }

    func catalog() throws -> LocalModelCatalog {
        LocalModelCatalog(
            schemaVersion: 1,
            generatedAt: Date(timeIntervalSince1970: 0),
            models: descriptors
        )
    }
}

private func replacingReleaseIdentity(
    _ release: LocalModelRelease,
    commit: String,
    engineRevision: String
) -> LocalModelRelease {
    LocalModelRelease(
        provider: release.provider,
        repository: release.repository,
        commit: commit,
        upstreamVersion: release.upstreamVersion,
        engineRevision: engineRevision,
        validatorKey: release.validatorKey,
        minimumValidatorVersion: release.minimumValidatorVersion,
        minimumAppVersion: release.minimumAppVersion,
        maximumAppVersion: release.maximumAppVersion,
        licenseIdentifier: release.licenseIdentifier,
        licenseDisplayName: release.licenseDisplayName,
        attributionIdentifier: release.attributionIdentifier,
        modelCardURL: release.modelCardURL,
        expectedPayloadBytes: release.expectedPayloadBytes,
        requiredFreeBytes: release.requiredFreeBytes,
        artifactCount: release.artifactCount,
        artifacts: release.artifacts,
        supportedLanguageCodes: release.supportedLanguageCodes,
        runtimeDirectoryName: release.runtimeDirectoryName
    )
}

private struct FixtureValidator: LocalModelValidating {
    let key: LocalModelValidatorKey
    let version = 1

    func prepareAndValidate(
        release: LocalModelRelease,
        stagedPayload: URL,
        preparedOutput: URL
    ) async throws -> LocalModelPreparedPayload {
        let runtime = preparedOutput.appending(
            path: release.runtimeDirectoryName,
            directoryHint: .isDirectory
        )
        try FileManager.default.copyItem(at: stagedPayload, to: runtime)
        return LocalModelPreparedPayload(payloadRoot: preparedOutput)
    }
}

private actor FixtureDownloader: LocalModelDownloading {
    private let data: Data
    private let gate: DownloadGate?
    private var calls = 0

    init(data: Data, gate: DownloadGate?) {
        self.data = data
        self.gate = gate
    }

    func download(
        _ request: LocalModelArtifactDownloadRequest,
        progress: @escaping LocalModelDownloadProgressHandler
    ) async throws {
        calls += 1
        if let gate {
            try await gate.wait()
        }
        try Task.checkCancellation()
        try data.write(to: request.destinationURL, options: .atomic)
        await progress(Int64(data.count))
    }

    func callCount() -> Int { calls }
}

private actor DownloadGate {
    private var isOpen = false
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var gateWaiter: CheckedContinuation<Void, any Error>?

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func wait() async throws {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        if isOpen { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { gateWaiter = $0 }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func open() {
        isOpen = true
        gateWaiter?.resume()
        gateWaiter = nil
    }

    private func cancel() {
        gateWaiter?.resume(throwing: CancellationError())
        gateWaiter = nil
    }
}
