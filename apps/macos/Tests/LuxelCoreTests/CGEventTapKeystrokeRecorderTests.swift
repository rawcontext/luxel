import Foundation
@testable import LuxelCore
import OSLog
import Testing

@Suite("CGEventTap keystroke recorder")
struct CGEventTapKeystrokeRecorderTests {
    @Test("disabled tap publishes recovery after a verified re-enable")
    func disabledTapPublishesRecovery() async {
        await expectRecovery(result: true, expectedStatus: .eventDeliveryRecovered)
    }

    @Test("failed tap recovery publishes unavailable")
    func failedTapRecoveryPublishesUnavailable() async {
        await expectRecovery(result: false, expectedStatus: .eventDeliveryUnavailable)
    }

    private func expectRecovery(
        result: Bool,
        expectedStatus: KeystrokeCaptureStatus
    ) async {
        let control = KeystrokeEventTapRecoveryControlStub(result: result)
        let recorder = CGEventTapKeystrokeRecorder(
            logger: Logger(subsystem: "media.luxel.tests", category: "Keystrokes"),
            tapRecoveryControl: control
        )
        var statuses = recorder.statusUpdates.makeAsyncIterator()
        #expect(await statuses.next() == .idle)

        recorder.handleEventTapInterruption()

        #expect(await statuses.next() == expectedStatus)
        #expect(control.callCount == 1)
    }
}

private final class KeystrokeEventTapRecoveryControlStub:
    KeystrokeEventTapRecoveryControlling,
    @unchecked Sendable {
    private let lock = NSLock()
    private let result: Bool
    private var calls = 0

    init(result: Bool) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func reenableAndCheck(_ eventTap: CFMachPort?) -> Bool {
        lock.withLock { calls += 1 }
        return result
    }
}
