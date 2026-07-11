import Foundation
@testable import LuxelCore
import OSLog
import Testing

@Suite("CGEventTap keystroke recorder")
struct CGEventTapKeystrokeRecorderTests {
    @Test("disabled tap publishes recovery after a verified re-enable")
    func disabledTapPublishesRecovery() async {
        let control = KeystrokeEventTapRecoveryControlStub(result: true)
        let recorder = CGEventTapKeystrokeRecorder(
            logger: Logger(subsystem: "media.luxel.tests", category: "Keystrokes"),
            tapRecoveryControl: control
        )
        var statuses = recorder.statusUpdates.makeAsyncIterator()
        #expect(await statuses.next() == .idle)

        recorder.handleEventTapInterruption()

        #expect(await statuses.next() == .eventDeliveryRecovered)
        #expect(control.callCount == 1)
    }

    @Test("failed tap recovery publishes unavailable")
    func failedTapRecoveryPublishesUnavailable() async {
        let control = KeystrokeEventTapRecoveryControlStub(result: false)
        let recorder = CGEventTapKeystrokeRecorder(
            logger: Logger(subsystem: "media.luxel.tests", category: "Keystrokes"),
            tapRecoveryControl: control
        )
        var statuses = recorder.statusUpdates.makeAsyncIterator()
        #expect(await statuses.next() == .idle)

        recorder.handleEventTapInterruption()

        #expect(await statuses.next() == .eventDeliveryUnavailable)
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
