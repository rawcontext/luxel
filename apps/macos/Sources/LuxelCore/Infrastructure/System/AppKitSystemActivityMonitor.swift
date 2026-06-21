import AppKit
import IOKit.ps

public final class AppKitSystemActivityMonitor: SystemActivityMonitor, @unchecked Sendable {
    public typealias PowerSourceObserverFactory =
        @Sendable (@escaping @Sendable () -> Void) -> @Sendable () -> Void

    private let workspaceNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private let screensDidSleepNotification: Notification.Name
    private let screensDidWakeNotification: Notification.Name
    private let sessionDidResignActiveNotification: Notification.Name
    private let sessionDidBecomeActiveNotification: Notification.Name
    private let displayChangeNotification: Notification.Name
    private let isOnBatteryPower: @Sendable () -> Bool
    private let startPowerSourceObserver: PowerSourceObserverFactory

    public convenience init() {
        self.init(
            workspaceNotificationCenter: NSWorkspace.shared.notificationCenter,
            applicationNotificationCenter: .default
        )
    }

    public init(
        workspaceNotificationCenter: NotificationCenter,
        applicationNotificationCenter: NotificationCenter,
        screensDidSleepNotification: Notification.Name = NSWorkspace.screensDidSleepNotification,
        screensDidWakeNotification: Notification.Name = NSWorkspace.screensDidWakeNotification,
        sessionDidResignActiveNotification: Notification.Name = NSWorkspace
            .sessionDidResignActiveNotification,
        sessionDidBecomeActiveNotification: Notification.Name = NSWorkspace
            .sessionDidBecomeActiveNotification,
        displayChangeNotification: Notification.Name = NSApplication
            .didChangeScreenParametersNotification,
        isOnBatteryPower: @escaping @Sendable () -> Bool = AppKitSystemActivityMonitor.isOnBatteryPower,
        startPowerSourceObserver: @escaping PowerSourceObserverFactory = AppKitSystemActivityMonitor
            .startIOKitPowerSourceObserver
    ) {
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        self.screensDidSleepNotification = screensDidSleepNotification
        self.screensDidWakeNotification = screensDidWakeNotification
        self.sessionDidResignActiveNotification = sessionDidResignActiveNotification
        self.sessionDidBecomeActiveNotification = sessionDidBecomeActiveNotification
        self.displayChangeNotification = displayChangeNotification
        self.isOnBatteryPower = isOnBatteryPower
        self.startPowerSourceObserver = startPowerSourceObserver
    }

    public var currentPauseReasons: Set<ReplayBufferPauseReason> {
        isOnBatteryPower() ? [.battery] : []
    }

    public func events() -> AsyncStream<SystemActivityEvent> {
        AsyncStream { continuation in
            let registrations = [
                observe(
                    center: workspaceNotificationCenter,
                    name: screensDidSleepNotification,
                    continuation: continuation,
                    event: .pauseReasonBecameActive(.displaySleep)
                ),
                observe(
                    center: workspaceNotificationCenter,
                    name: screensDidWakeNotification,
                    continuation: continuation,
                    event: .pauseReasonBecameInactive(.displaySleep)
                ),
                observe(
                    center: workspaceNotificationCenter,
                    name: sessionDidResignActiveNotification,
                    continuation: continuation,
                    event: .pauseReasonBecameActive(.locked)
                ),
                observe(
                    center: workspaceNotificationCenter,
                    name: sessionDidBecomeActiveNotification,
                    continuation: continuation,
                    event: .pauseReasonBecameInactive(.locked)
                ),
                observe(
                    center: applicationNotificationCenter,
                    name: displayChangeNotification,
                    continuation: continuation,
                    event: .displayConfigurationChanged
                )
            ]
            let cancelPowerSourceObserver = startPowerSourceObserver { [isOnBatteryPower] in
                continuation.yield(
                    isOnBatteryPower()
                        ? .pauseReasonBecameActive(.battery)
                        : .pauseReasonBecameInactive(.battery)
                )
            }

            continuation.onTermination = { _ in
                registrations.forEach { $0.cancel() }
                cancelPowerSourceObserver()
            }
        }
    }

    private func observe(
        center: NotificationCenter,
        name: Notification.Name,
        continuation: AsyncStream<SystemActivityEvent>.Continuation,
        event: SystemActivityEvent
    ) -> NotificationRegistration {
        let observer = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            continuation.yield(event)
        }
        return NotificationRegistration(center: center, observer: observer)
    }

    public static func isOnBatteryPower() -> Bool {
        guard let adapterDetails = IOPSCopyExternalPowerAdapterDetails() else {
            return true
        }

        _ = adapterDetails.takeRetainedValue()
        return false
    }

    public static func startIOKitPowerSourceObserver(
        onChange: @escaping @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let box = PowerSourceCallbackBox(onChange: onChange)
        let context = Unmanaged.passRetained(box).toOpaque()
        guard
            let runLoopSource = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else {
                        return
                    }

                    Unmanaged<PowerSourceCallbackBox>
                        .fromOpaque(context)
                        .takeUnretainedValue()
                        .onChange()
                }, context)?.takeRetainedValue()
        else {
            Unmanaged<PowerSourceCallbackBox>.fromOpaque(context).release()
            return {}
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        let registration = PowerSourceRunLoopRegistration(
            runLoopSource: runLoopSource,
            context: context
        )
        return {
            registration.cancel()
        }
    }
}

private struct NotificationRegistration: @unchecked Sendable {
    let center: NotificationCenter
    let observer: any NSObjectProtocol

    func cancel() {
        center.removeObserver(observer)
    }
}

private final class PowerSourceCallbackBox: @unchecked Sendable {
    let onChange: @Sendable () -> Void

    init(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
    }
}

private final class PowerSourceRunLoopRegistration: @unchecked Sendable {
    private let runLoopSource: CFRunLoopSource
    private let context: UnsafeMutableRawPointer
    private let lock = NSLock()
    private var isCancelled = false

    init(
        runLoopSource: CFRunLoopSource,
        context: UnsafeMutableRawPointer
    ) {
        self.runLoopSource = runLoopSource
        self.context = context
    }

    func cancel() {
        let shouldCancel = lock.withLock {
            guard !isCancelled else {
                return false
            }

            isCancelled = true
            return true
        }
        guard shouldCancel else {
            return
        }

        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        Unmanaged<PowerSourceCallbackBox>.fromOpaque(context).release()
    }

    deinit {
        cancel()
    }
}
