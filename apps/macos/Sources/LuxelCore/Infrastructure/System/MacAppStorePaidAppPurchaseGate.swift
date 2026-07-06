import Foundation
import StoreKit

public struct MacAppStorePaidAppPurchaseGate: PurchaseGate {
    public enum AppTransactionEntitlement: Sendable {
        case verified(bundleID: String)
        case unverified
        case unavailable
    }

    private let receiptURL: @Sendable () -> URL?
    private let currentBundleID: @Sendable () -> String?
    private let appTransactionEntitlement: @Sendable () async -> AppTransactionEntitlement

    public init(
        receiptURL: @escaping @Sendable () -> URL? = {
            Self.currentAppStoreReceiptURL()
        },
        currentBundleID: @escaping @Sendable () -> String? = {
            Bundle.main.bundleIdentifier
        },
        appTransactionEntitlement: @escaping @Sendable () async -> AppTransactionEntitlement = {
            await Self.currentAppTransactionEntitlement()
        }
    ) {
        self.receiptURL = receiptURL
        self.currentBundleID = currentBundleID
        self.appTransactionEntitlement = appTransactionEntitlement
    }

    public func isEntitled() async -> Bool {
        if Self.isTestFlightReceipt(receiptURL()) {
            return true
        }

        guard let currentBundleID = currentBundleID() else {
            return false
        }

        switch await appTransactionEntitlement() {
        case .verified(let appTransactionBundleID):
            return appTransactionBundleID == currentBundleID
        case .unverified:
            return false
        case .unavailable:
            return true
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

    public static func isTestFlightReceipt(_ receiptURL: URL?) -> Bool {
        receiptURL?.lastPathComponent == "sandboxReceipt"
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

    @usableFromInline
    static func currentAppStoreReceiptURL() -> URL? {
        let receiptDirectoryURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("_MASReceipt", isDirectory: true)
        let sandboxReceiptURL = receiptDirectoryURL.appendingPathComponent("sandboxReceipt")

        if FileManager.default.fileExists(atPath: sandboxReceiptURL.path) {
            return sandboxReceiptURL
        }

        let productionReceiptURL = receiptDirectoryURL.appendingPathComponent("receipt")
        if FileManager.default.fileExists(atPath: productionReceiptURL.path) {
            return productionReceiptURL
        }

        return nil
    }
}
