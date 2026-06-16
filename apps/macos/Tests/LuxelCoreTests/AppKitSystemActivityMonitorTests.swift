import Foundation
import LuxelCore
import Testing

@Suite("AppKit system activity monitor")
struct AppKitSystemActivityMonitorTests {
    @Test("current pause reasons include battery when running on battery power")
    func currentPauseReasonsIncludeBatteryWhenRunningOnBatteryPower() {
        let batteryState = BatteryStateProbe(isOnBattery: true)
        let monitor = AppKitSystemActivityMonitor(
            workspaceNotificationCenter: NotificationCenter(),
            applicationNotificationCenter: NotificationCenter(),
            isOnBatteryPower: { batteryState.isOnBattery },
            startPowerSourceObserver: { _ in {} }
        )

        #expect(monitor.currentPauseReasons == [.battery])

        batteryState.isOnBattery = false
        #expect(monitor.currentPauseReasons == [])
    }

    @Test("notifications map to system activity events")
    func notificationsMapToSystemActivityEvents() async {
        let workspaceCenter = NotificationCenter()
        let applicationCenter = NotificationCenter()
        let powerProbe = PowerSourceProbe()
        let screensDidSleep = Notification.Name("tests.screensDidSleep")
        let screensDidWake = Notification.Name("tests.screensDidWake")
        let sessionDidResign = Notification.Name("tests.sessionDidResign")
        let sessionDidBecome = Notification.Name("tests.sessionDidBecome")
        let displayChanged = Notification.Name("tests.displayChanged")
        let monitor = AppKitSystemActivityMonitor(
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: applicationCenter,
            screensDidSleepNotification: screensDidSleep,
            screensDidWakeNotification: screensDidWake,
            sessionDidResignActiveNotification: sessionDidResign,
            sessionDidBecomeActiveNotification: sessionDidBecome,
            displayChangeNotification: displayChanged,
            isOnBatteryPower: { false },
            startPowerSourceObserver: powerProbe.start
        )
        var iterator = monitor.events().makeAsyncIterator()

        workspaceCenter.post(name: screensDidSleep, object: nil)
        workspaceCenter.post(name: screensDidWake, object: nil)
        workspaceCenter.post(name: sessionDidResign, object: nil)
        workspaceCenter.post(name: sessionDidBecome, object: nil)
        applicationCenter.post(name: displayChanged, object: nil)

        #expect(await iterator.next() == .pauseReasonBecameActive(.displaySleep))
        #expect(await iterator.next() == .pauseReasonBecameInactive(.displaySleep))
        #expect(await iterator.next() == .pauseReasonBecameActive(.locked))
        #expect(await iterator.next() == .pauseReasonBecameInactive(.locked))
        #expect(await iterator.next() == .displayConfigurationChanged)
    }

    @Test("power source callback maps current battery state")
    func powerSourceCallbackMapsCurrentBatteryState() async {
        let batteryState = BatteryStateProbe(isOnBattery: false)
        let powerProbe = PowerSourceProbe()
        let monitor = AppKitSystemActivityMonitor(
            workspaceNotificationCenter: NotificationCenter(),
            applicationNotificationCenter: NotificationCenter(),
            isOnBatteryPower: { batteryState.isOnBattery },
            startPowerSourceObserver: powerProbe.start
        )
        var iterator = monitor.events().makeAsyncIterator()

        batteryState.isOnBattery = true
        powerProbe.emit()
        #expect(await iterator.next() == .pauseReasonBecameActive(.battery))

        batteryState.isOnBattery = false
        powerProbe.emit()
        #expect(await iterator.next() == .pauseReasonBecameInactive(.battery))
    }
}

private final class BatteryStateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(isOnBattery: Bool) {
        value = isOnBattery
    }

    var isOnBattery: Bool {
        get {
            lock.withLock {
                value
            }
        }
        set {
            lock.withLock {
                value = newValue
            }
        }
    }
}

private final class PowerSourceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable () -> Void)?

    func start(_ callback: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        lock.withLock {
            self.callback = callback
        }
        return { [weak self] in
            self?.lock.withLock {
                self?.callback = nil
            }
        }
    }

    func emit() {
        lock.withLock {
            callback
        }?()
    }
}
