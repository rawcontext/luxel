import Foundation
import StoreKit

public struct MacAppStorePaidAppPurchaseGate: PurchaseGate {
    public enum AppTransactionEntitlement: Sendable {
        case verified(bundleID: String)
        case unverified
        case unavailable
    }

    private let currentBundleID: @Sendable () -> String?
    private let appTransactionEntitlement: @Sendable () async -> AppTransactionEntitlement

    public init(
        currentBundleID: @escaping @Sendable () -> String? = {
            Bundle.main.bundleIdentifier
        },
        appTransactionEntitlement: @escaping @Sendable () async -> AppTransactionEntitlement = {
            await Self.currentAppTransactionEntitlement()
        }
    ) {
        self.currentBundleID = currentBundleID
        self.appTransactionEntitlement = appTransactionEntitlement
    }

    public func isEntitled() async -> Bool {
        guard let currentBundleID = currentBundleID() else {
            return false
        }

        switch await appTransactionEntitlement() {
        case .verified(let appTransactionBundleID):
            return appTransactionBundleID == currentBundleID
        case .unverified, .unavailable:
            return false
        }
    }

    public func entitlementChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(await isEntitled())
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    @usableFromInline
    static func currentAppTransactionEntitlement() async -> AppTransactionEntitlement {
        do {
            switch try await AppTransaction.shared {
            case .verified(let appTransaction):
                return .verified(bundleID: appTransaction.bundleID)
            case .unverified:
                return .unverified
            }
        } catch {
            return .unavailable
        }
    }
}
