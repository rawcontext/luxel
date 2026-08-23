import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog

public final class CGEventTapKeystrokeRecorder: KeystrokeCaptureEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private let logger: Logger
    private let tapRecoveryControl: any KeystrokeEventTapRecoveryControlling
    private var eventContinuation: AsyncStream<KeystrokeSourceEvent>.Continuation?
    private var statusContinuations: [UUID: AsyncStream<KeystrokeCaptureStatus>.Continuation] = [:]
    private var runLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var startedAtUptime: TimeInterval?
    private var isUserPaused = false
    private var isRecordingPaused = false
    private var isSecureInputPaused = false

    public convenience init(
        logger: Logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.rawcontext.luxel",
            category: "KeystrokeCapture"
        )
    ) {
        self.init(logger: logger, tapRecoveryControl: SystemKeystrokeEventTapRecoveryControl())
    }

    init(
        logger: Logger,
        tapRecoveryControl: any KeystrokeEventTapRecoveryControlling
    ) {
        self.logger = logger
        self.tapRecoveryControl = tapRecoveryControl
    }

    deinit {
        stop()
    }

    public var statusUpdates: AsyncStream<KeystrokeCaptureStatus> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let id = UUID()
            lock.withLock {
                statusContinuations[id] = continuation
            }
            continuation.yield(currentStatus)
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.statusContinuations[id] = nil
                }
            }
        }
    }

    public func events() -> AsyncStream<KeystrokeSourceEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let shouldStart = lock.withLock { () -> Bool in
                guard eventContinuation == nil else {
                    continuation.finish()
                    return false
                }
                eventContinuation = continuation
                startedAtUptime = ProcessInfo.processInfo.systemUptime
                return true
            }

            guard shouldStart else {
                return
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
            let thread = Thread { [weak self] in
                self?.runEventTap()
            }
            thread.name = "Luxel keystroke event tap"
            thread.qualityOfService = .userInteractive
            thread.start()
        }
    }

    public func setUserPaused(_ isPaused: Bool) {
        let transition = lock.withLock { () -> ([KeystrokeSourceEvent], KeystrokeCaptureStatus)? in
            guard eventContinuation != nil, self.isUserPaused != isPaused else {
                return nil
            }

            let previousCause = effectivePauseCause
            self.isUserPaused = isPaused
            return (pauseTransitionEvents(from: previousCause), resolvedStatus)
        }

        guard let transition else {
            return
        }
        for event in transition.0 {
            yield(event)
        }
        yieldStatus(transition.1)
    }

    public func setRecordingPaused(_ isPaused: Bool) {
        let transition = lock.withLock { () -> ([KeystrokeSourceEvent], KeystrokeCaptureStatus)? in
            guard eventContinuation != nil, self.isRecordingPaused != isPaused else {
                return nil
            }

            let previousCause = effectivePauseCause
            self.isRecordingPaused = isPaused
            return (pauseTransitionEvents(from: previousCause), resolvedStatus)
        }

        guard let transition else {
            return
        }
        for event in transition.0 {
            yield(event)
        }
        yieldStatus(transition.1)
    }

    public func stop() {
        let stopped = lock.withLock { () -> KeystrokeRecorderStopState in
            let state = KeystrokeRecorderStopState(
                continuation: eventContinuation,
                runLoop: runLoop,
                eventTap: eventTap
            )
            eventContinuation = nil
            runLoop = nil
            eventTap = nil
            startedAtUptime = nil
            isUserPaused = false
            isRecordingPaused = false
            isSecureInputPaused = false
            return state
        }

        if let eventTap = stopped.eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let runLoop = stopped.runLoop {
            CFRunLoopStop(runLoop)
            CFRunLoopWakeUp(runLoop)
        }
        stopped.continuation?.finish()
        yieldStatus(.idle)
    }
}

extension CGEventTapKeystrokeRecorder {
    private func runEventTap() {
        guard CGPreflightListenEventAccess() else {
            finishUnavailable(status: .permissionDenied)
            return
        }

        let mask =
            (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }
                    let recorder = Unmanaged<CGEventTapKeystrokeRecorder>
                        .fromOpaque(userInfo)
                        .takeUnretainedValue()
                    recorder.handle(type: type, event: event)
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            finishUnavailable(status: .eventDeliveryUnavailable)
            return
        }

        let currentRunLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        lock.withLock {
            runLoop = currentRunLoop
            eventTap = tap
        }
        CFRunLoopAddSource(currentRunLoop, source, .commonModes)
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollSecureInput()
        }
        pollSecureInput()
        yieldStatus(.active)
        CFRunLoopRun()
        CFRunLoopRemoveSource(currentRunLoop, source, .commonModes)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            handleEventTapInterruption()
            return
        }

        let shouldIgnore = lock.withLock {
            eventContinuation == nil || isUserPaused || isRecordingPaused || isSecureInputPaused
        }
        guard !shouldIgnore else {
            return
        }

        let sourceEvent: KeystrokeSourceEvent?
        switch type {
        case .keyDown:
            sourceEvent = .keyDown(
                wallTime: wallTime,
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                characters: Self.characters(in: event),
                modifiers: Self.modifiers(from: event.flags),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
        case .flagsChanged:
            sourceEvent = .flagsChanged(
                wallTime: wallTime,
                keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: Self.modifiers(from: event.flags)
            )
        default:
            sourceEvent = nil
        }

        if let sourceEvent {
            yield(sourceEvent)
        }
    }

    private func pollSecureInput() {
        let isSecureInputEnabled = IsSecureEventInputEnabled()
        let transition = lock.withLock { () -> ([KeystrokeSourceEvent], KeystrokeCaptureStatus)? in
            guard eventContinuation != nil,
                isSecureInputPaused != isSecureInputEnabled
            else {
                return nil
            }

            let previousCause = effectivePauseCause
            isSecureInputPaused = isSecureInputEnabled
            return (pauseTransitionEvents(from: previousCause), resolvedStatus)
        }

        guard let transition else {
            return
        }
        for event in transition.0 {
            yield(event)
        }
        yieldStatus(transition.1)
    }

    func handleEventTapInterruption() {
        let eventTap = lock.withLock { self.eventTap }
        guard tapRecoveryControl.reenableAndCheck(eventTap) else {
            logger.error("Keystroke event tap was disabled and could not be restored")
            finishUnavailable(status: .eventDeliveryUnavailable)
            return
        }

        logger.warning("Keystroke event tap was disabled and has been re-enabled")
        yieldStatus(.eventDeliveryRecovered)
        yieldStatus(currentStatus)
    }

    private func finishUnavailable(status: KeystrokeCaptureStatus) {
        let continuation = lock.withLock { () -> AsyncStream<KeystrokeSourceEvent>.Continuation? in
            let continuation = eventContinuation
            eventContinuation = nil
            startedAtUptime = nil
            return continuation
        }
        yieldStatus(status)
        continuation?.finish()
    }

    private var wallTime: TimeInterval {
        guard let startedAtUptime else {
            return 0
        }
        return max(0, ProcessInfo.processInfo.systemUptime - startedAtUptime)
    }

    private var resolvedStatus: KeystrokeCaptureStatus {
        if isSecureInputPaused {
            return .paused(.secureInput)
        }
        if isRecordingPaused {
            return .paused(.recording)
        }
        if isUserPaused {
            return .paused(.user)
        }
        return eventContinuation == nil ? .idle : .active
    }

    private var effectivePauseCause: KeystrokePauseCause? {
        if isSecureInputPaused {
            return .secureInput
        }
        if isRecordingPaused {
            return .recording
        }
        return isUserPaused ? .user : nil
    }

    private func pauseTransitionEvents(
        from previousCause: KeystrokePauseCause?
    ) -> [KeystrokeSourceEvent] {
        let nextCause = effectivePauseCause
        guard previousCause != nextCause else {
            return []
        }
        let time = wallTime
        var events: [KeystrokeSourceEvent] = []
        if let previousCause {
            events.append(.pauseEnded(wallTime: time, cause: previousCause))
        }
        if let nextCause {
            events.append(.pauseStarted(wallTime: time, cause: nextCause))
        }
        return events
    }

    private var currentStatus: KeystrokeCaptureStatus {
        lock.withLock { resolvedStatus }
    }

    private func yield(_ event: KeystrokeSourceEvent) {
        lock.withLock { eventContinuation }?.yield(event)
    }

    private func yieldStatus(_ status: KeystrokeCaptureStatus) {
        let continuations = lock.withLock { Array(statusContinuations.values) }
        for continuation in continuations {
            continuation.yield(status)
        }
    }

    private static func modifiers(from flags: CGEventFlags) -> Set<KeystrokeModifier> {
        var modifiers: Set<KeystrokeModifier> = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskSecondaryFn) { modifiers.insert(.function) }
        return modifiers
    }

    private static func characters(in event: CGEvent) -> String? {
        var length = 0
        event.keyboardGetUnicodeString(
            maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else {
            return nil
        }

        var characters = [UniChar](repeating: 0, count: length)
        event.keyboardGetUnicodeString(
            maxStringLength: length,
            actualStringLength: &length,
            unicodeString: &characters
        )
        return String(utf16CodeUnits: characters, count: length)
    }
}

private struct KeystrokeRecorderStopState {
    let continuation: AsyncStream<KeystrokeSourceEvent>.Continuation?
    let runLoop: CFRunLoop?
    let eventTap: CFMachPort?
}

protocol KeystrokeEventTapRecoveryControlling: Sendable {
    func reenableAndCheck(_ eventTap: CFMachPort?) -> Bool
}

private struct SystemKeystrokeEventTapRecoveryControl: KeystrokeEventTapRecoveryControlling {
    func reenableAndCheck(_ eventTap: CFMachPort?) -> Bool {
        guard let eventTap else {
            return false
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return CGEvent.tapIsEnabled(tap: eventTap)
    }
}
