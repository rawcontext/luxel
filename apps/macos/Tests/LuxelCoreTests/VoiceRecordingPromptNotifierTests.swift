import Foundation
@testable import LuxelCore
import Testing
@preconcurrency import UserNotifications

@Suite("Speech prompt notifications")
struct VoiceRecordingPromptNotificationTests {
    @Test("authorization reads and requests through the contextual notification port")
    func authorization() async {
        let center = PromptNotificationCenterSpy(
            currentAuthorization: .notDetermined,
            requestedAuthorization: .authorized
        )
        let notifier = UserNotificationsSpeechPromptNotifier(center: center)

        #expect(await notifier.authorizationStatus() == .notDetermined)
        #expect(await notifier.requestAuthorization() == .authorized)
        #expect(center.authorizationRequestCount == 1)
    }

    @Test("posting replaces only the stable speech prompt request")
    func postReplacesPrompt() async throws {
        let center = PromptNotificationCenterSpy()
        let notifier = UserNotificationsSpeechPromptNotifier(center: center)

        try await notifier.postPrompt()
        try await notifier.postPrompt()

        let requests = center.requestSnapshots
        #expect(requests.map(\.identifier) == [
            VoiceDetectionNotificationIdentifiers.request,
            VoiceDetectionNotificationIdentifiers.request
        ])
        #expect(requests.last?.categoryIdentifier
                    == VoiceDetectionNotificationIdentifiers.category)
        #expect(requests.last?.title.isEmpty == false)
        #expect(requests.last?.body.isEmpty == false)
        #expect(requests.last?.hasSound == true)
        #expect(center.removedPendingIdentifiers == [
            [VoiceDetectionNotificationIdentifiers.request],
            [VoiceDetectionNotificationIdentifiers.request]
        ])
        #expect(center.removedDeliveredIdentifiers == [
            [VoiceDetectionNotificationIdentifiers.request],
            [VoiceDetectionNotificationIdentifiers.request]
        ])
    }

    @Test("removal cannot affect unrelated notifications")
    func removalScope() async {
        let center = PromptNotificationCenterSpy()
        let notifier = UserNotificationsSpeechPromptNotifier(center: center)

        await notifier.removePrompt()

        #expect(center.removedPendingIdentifiers
                    == [[VoiceDetectionNotificationIdentifiers.request]])
        #expect(center.removedDeliveredIdentifiers
                    == [[VoiceDetectionNotificationIdentifiers.request]])
    }
}

private final class PromptNotificationCenterSpy:
    VoiceRecordingPromptNotificationCenter,
    @unchecked Sendable {
    let currentAuthorization: VoiceDetectionAuthorizationStatus
    let requestedAuthorization: VoiceDetectionAuthorizationStatus
    private let lock = NSLock()
    private var requestCount = 0
    private var requests: [PromptRequestSnapshot] = []
    private var removedPending: [[String]] = []
    private var removedDelivered: [[String]] = []

    init(
        currentAuthorization: VoiceDetectionAuthorizationStatus = .authorized,
        requestedAuthorization: VoiceDetectionAuthorizationStatus = .authorized
    ) {
        self.currentAuthorization = currentAuthorization
        self.requestedAuthorization = requestedAuthorization
    }

    func authorizationStatus() -> VoiceDetectionAuthorizationStatus {
        currentAuthorization
    }

    func requestAuthorization() -> VoiceDetectionAuthorizationStatus {
        lock.withLock {
            requestCount += 1
        }
        return requestedAuthorization
    }

    func add(_ request: UNNotificationRequest) {
        lock.withLock {
            requests.append(
                PromptRequestSnapshot(
                    identifier: request.identifier,
                    categoryIdentifier: request.content.categoryIdentifier,
                    title: request.content.title,
                    body: request.content.body,
                    hasSound: request.content.sound != nil
                )
            )
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            removedPending.append(identifiers)
        }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        lock.withLock {
            removedDelivered.append(identifiers)
        }
    }

    var authorizationRequestCount: Int {
        lock.withLock { requestCount }
    }

    var requestSnapshots: [PromptRequestSnapshot] {
        lock.withLock { requests }
    }

    var removedPendingIdentifiers: [[String]] {
        lock.withLock { removedPending }
    }

    var removedDeliveredIdentifiers: [[String]] {
        lock.withLock { removedDelivered }
    }
}

private struct PromptRequestSnapshot: Sendable {
    let identifier: String
    let categoryIdentifier: String
    let title: String
    let body: String
    let hasSound: Bool
}
