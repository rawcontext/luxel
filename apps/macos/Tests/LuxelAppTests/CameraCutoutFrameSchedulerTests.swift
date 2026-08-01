import Foundation
import Testing
@testable import LuxelApp

@Suite("Camera Cutout frame scheduler")
struct CameraCutoutFrameSchedulerTests {
    @Test("keeps one active frame and replaces the one pending frame")
    func keepsOneActiveAndOneLatestPendingFrame() async throws {
        let harness = makeSchedulerHarness()

        harness.scheduler.start()
        harness.scheduler.submit(1)
        try await waitUntil { harness.firstStarted.value }
        harness.scheduler.submit(2)
        harness.scheduler.submit(3)

        #expect(
            harness.scheduler.snapshot
                == CameraCutoutSchedulerSnapshot(
                    inFlightCount: 1,
                    pendingCount: 1,
                    droppedFrameCount: 1
                )
        )

        harness.releaseFirst.signal()
        try await waitUntil { harness.outputs.values == [1, 3] }
        #expect(harness.scheduler.snapshot.inFlightCount == 0)
        #expect(harness.scheduler.snapshot.pendingCount == 0)
    }

    @Test("ignores a late result after teardown and restart")
    func ignoresLateResultAfterTeardownAndRestart() async throws {
        let harness = makeSchedulerHarness()

        harness.scheduler.start()
        harness.scheduler.submit(1)
        try await waitUntil { harness.firstStarted.value }
        harness.scheduler.stop()
        harness.scheduler.start()
        harness.scheduler.submit(2)
        harness.releaseFirst.signal()

        try await waitUntil { harness.outputs.values == [2] }
        #expect(harness.outputs.values == [2])
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @Sendable () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out waiting for scheduler output")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeSchedulerHarness() -> SchedulerHarness {
        let firstStarted = LockedFlag()
        let releaseFirst = DispatchSemaphore(value: 0)
        let outputs = LockedValues<Int>()
        let scheduler = CameraCutoutFrameScheduler<Int, Int>(
            process: { frame, _ in
                if frame == 1 {
                    firstStarted.set()
                    releaseFirst.wait()
                }
                return frame
            },
            onOutput: { outputs.append($0) },
            onFailure: { _ in }
        )
        return SchedulerHarness(
            scheduler: scheduler,
            firstStarted: firstStarted,
            releaseFirst: releaseFirst,
            outputs: outputs
        )
    }
}

private struct SchedulerHarness {
    let scheduler: CameraCutoutFrameScheduler<Int, Int>
    let firstStarted: LockedFlag
    let releaseFirst: DispatchSemaphore
    let outputs: LockedValues<Int>
}

private final class LockedValues<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.withLock { storage }
    }

    func append(_ value: Value) {
        lock.withLock { storage.append(value) }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.withLock { storage }
    }

    func set() {
        lock.withLock { storage = true }
    }
}
