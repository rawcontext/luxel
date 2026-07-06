import Foundation
import StoreKit

public struct MacAppStorePaidAppPurchaseGate: PurchaseGate {
    public init() {}

    public func isEntitled() async -> Bool {
        do {
            switch try await AppTransaction.shared {
            case .verified(let appTransaction):
                return appTransaction.bundleID == Bundle.main.bundleIdentifier
            case .unverified:
                return false
            }
        } catch {
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
}
