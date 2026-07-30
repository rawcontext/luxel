import Foundation
@testable import LuxelCore
import Speech
import Testing

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
        let probe = AssetReadinessProbe(statuses: [.unsupported, .installed])
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

        let counts = await probe.counts()
        #expect(counts.status == 2)
        #expect(counts.install == 0)
        #expect(counts.sleep == 1)
    }

    @Test("asset readiness starts installation and waits for completion")
    func assetReadinessStartsInstallationAndWaitsForCompletion() async throws {
        let probe = AssetReadinessProbe(statuses: [.supported, .downloading, .installed])
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

        let counts = await probe.counts()
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
