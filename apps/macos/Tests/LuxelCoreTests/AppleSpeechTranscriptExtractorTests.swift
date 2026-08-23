import Foundation
import Speech
import Testing

@testable import LuxelCore

@Suite("Apple Speech transcript extractor")
struct AppleSpeechTranscriptExtractorTests {
    @Test("extractor requires Speech authorization before reading audio")
    func extractorRequiresSpeechAuthorization() async throws {
        let extractor = AppleSpeechTranscriptExtractor(
            speechAuthorizationStatus: { .denied }
        )

        await #expect(throws: AppleSpeechTranscriptError.authorizationDenied) {
            _ = try await extractor.transcribe(
                TimedSpeechTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/missing-audio.m4a"),
                    locale: Locale(identifier: "en_US")
                ))
        }
    }

    @Test("asset readiness waits through a transient unsupported status")
    func assetReadinessWaitsThroughTransientUnsupportedStatus() async throws {
        let counts = try await waitForAssets(statuses: [.unsupported, .installed])
        #expect(counts.status == 2)
        #expect(counts.install == 0)
        #expect(counts.sleep == 1)
    }

    @Test("asset readiness accepts an installed locale when asset status is stale")
    func assetReadinessAcceptsInstalledLocaleWhenStatusIsStale() async throws {
        let installedProbe = InstalledLocaleProbe(values: [false, true])
        let assetProbe = AssetReadinessProbe(statuses: [.unsupported])
        let waiter = AppleSpeechAssetReadinessWaiter(
            retryInterval: .zero,
            maximumTransientAttempts: 2,
            maximumDownloadPolls: 2
        )

        try await waiter.waitUntilReady(
            installed: { await installedProbe.nextValue() },
            status: { await assetProbe.nextStatus() },
            install: { await assetProbe.recordInstall() },
            sleep: { _ in await assetProbe.recordSleep() }
        )

        let counts = await assetProbe.counts()
        #expect(await installedProbe.count == 2)
        #expect(counts.status == 1)
        #expect(counts.install == 0)
        #expect(counts.sleep == 1)
    }

    @Test("asset readiness starts installation and waits for completion")
    func assetReadinessStartsInstallationAndWaitsForCompletion() async throws {
        let counts = try await waitForAssets(statuses: [.supported, .downloading, .installed])
        #expect(counts.status == 3)
        #expect(counts.install == 1)
        #expect(counts.sleep == 2)
    }

    @Test("asset readiness fails after bounded transient retries")
    func assetReadinessFailsAfterBoundedTransientRetries() async {
        let probe = AssetReadinessProbe(statuses: [.unsupported])
        let waiter = AppleSpeechAssetReadinessWaiter(
            retryInterval: .zero,
            maximumTransientAttempts: 2,
            maximumDownloadPolls: 2
        )

        await #expect(throws: AppleSpeechTranscriptError.assetsUnavailable) {
            try await waiter.waitUntilReady(
                status: { await probe.nextStatus() },
                install: { await probe.recordInstall() },
                sleep: { _ in await probe.recordSleep() }
            )
        }

        let counts = await probe.counts()
        #expect(counts.status == 2)
        #expect(counts.sleep == 1)
    }

    @Test("asset readiness waiting is cancellable")
    func assetReadinessWaitingIsCancellable() async {
        let waiter = AppleSpeechAssetReadinessWaiter(
            retryInterval: .seconds(10),
            maximumTransientAttempts: 2,
            maximumDownloadPolls: 2
        )
        let task = Task {
            try await waiter.waitUntilReady(
                status: { .downloading },
                install: {},
                sleep: { duration in try await Task.sleep(for: duration) }
            )
        }

        await Task.yield()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("asset readiness gate coalesces concurrent checks for one locale")
    func assetReadinessGateCoalescesConcurrentChecks() async throws {
        let gate = AppleSpeechAssetReadinessGate()
        let counter = AsyncCounter()

        async let first: Void = gate.wait(for: "en_US") {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
        }
        async let second: Void = gate.wait(for: "en_US") {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(50))
        }

        _ = try await (first, second)
        #expect(await counter.value == 1)
    }

    @Test("asset failures have actionable descriptions")
    func assetFailuresHaveActionableDescriptions() {
        #expect(
            AppleSpeechTranscriptError.assetsUnavailable.localizedDescription
                == "Speech transcription could not finish preparing. Wait a moment, then retry."
        )
    }

    private func waitForAssets(
        statuses: [AppleSpeechAssetStatus]
    ) async throws -> AssetReadinessProbe.Counts {
        let probe = AssetReadinessProbe(statuses: statuses)
        let waiter = AppleSpeechAssetReadinessWaiter(
            retryInterval: .zero,
            maximumTransientAttempts: 2,
            maximumDownloadPolls: 2
        )
        try await waiter.waitUntilReady(
            status: { await probe.nextStatus() },
            install: { await probe.recordInstall() },
            sleep: { _ in await probe.recordSleep() }
        )
        return await probe.counts()
    }
}

private actor InstalledLocaleProbe {
    private let values: [Bool]
    private var index = 0
    private(set) var count = 0

    init(values: [Bool]) {
        self.values = values
    }

    func nextValue() -> Bool {
        let value = values[min(index, values.count - 1)]
        index += 1
        count += 1
        return value
    }
}

private actor AssetReadinessProbe {
    struct Counts: Sendable {
        let status: Int
        let install: Int
        let sleep: Int
    }

    private let statuses: [AppleSpeechAssetStatus]
    private var statusIndex = 0
    private var statusCount = 0
    private var installCount = 0
    private var sleepCount = 0

    init(statuses: [AppleSpeechAssetStatus]) {
        self.statuses = statuses
    }

    func nextStatus() -> AppleSpeechAssetStatus {
        let status = statuses[min(statusIndex, statuses.count - 1)]
        statusIndex += 1
        statusCount += 1
        return status
    }

    func recordInstall() {
        installCount += 1
    }

    func recordSleep() {
        sleepCount += 1
    }

    func counts() -> Counts {
        Counts(status: statusCount, install: installCount, sleep: sleepCount)
    }
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
