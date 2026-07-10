import CryptoKit
import Foundation
import LuxelCore
import Testing

struct FixtureModelEnvironment {
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
        let release = Self.makeRelease(artifact: artifact, validatorKey: validatorKey)
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

    private static func makeRelease(
        artifact: LocalModelArtifact,
        validatorKey: LocalModelValidatorKey
    ) -> LocalModelRelease {
        LocalModelRelease(
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
    }
}

extension LocalModelDescriptor {
    func replacingID(_ id: LocalModelID) -> LocalModelDescriptor {
        LocalModelDescriptor(
            id: id,
            displayNameKey: displayNameKey,
            featureNameKey: featureNameKey,
            summaryKey: summaryKey,
            downloadDisclosureKey: downloadDisclosureKey,
            removalWarningKey: removalWarningKey,
            category: category,
            mayBeShared: mayBeShared,
            licenseURL: licenseURL,
            currentRelease: currentRelease,
            previousRelease: previousRelease
        )
    }
}

struct FixtureCatalogProvider: LocalModelCatalogProviding {
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

func replacingReleaseIdentity(
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

struct FixtureValidator: LocalModelValidating {
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

actor FixtureDownloader: LocalModelDownloading {
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

actor DownloadGate {
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
