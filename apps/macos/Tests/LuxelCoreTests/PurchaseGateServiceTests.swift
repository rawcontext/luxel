import Foundation
import LuxelCore
import Testing

@Suite("Purchase gate service")
struct PurchaseGateServiceTests {
    @Test("service forwards entitlement state")
    func serviceForwardsEntitlementState() async {
        let service = PurchaseGateService(gate: StubPurchaseGate(isEntitled: false))

        #expect(await !service.isEntitled())
    }

    @Test("service forwards entitlement changes")
    func serviceForwardsEntitlementChanges() async throws {
        let service = PurchaseGateService(gate: StubPurchaseGate(changes: [true, false]))
        var iterator = service.entitlementChanges().makeAsyncIterator()

        let firstChange = await iterator.next()
        let secondChange = await iterator.next()

        #expect(firstChange == true)
        #expect(secondChange == false)
    }

    @Test("developer ID gate is always entitled")
    func developerIDGateIsAlwaysEntitled() async throws {
        let gate = AlwaysEntitledPurchaseGate()
        var iterator = gate.entitlementChanges().makeAsyncIterator()

        #expect(await gate.isEntitled())
        #expect(await iterator.next() == true)
    }

    @Test("Mac App Store gate allows TestFlight sandbox receipts")
    func macAppStoreGateAllowsTestFlightSandboxReceipts() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            receiptURL: {
                URL(fileURLWithPath: "/Applications/Luxel.app/Contents/_MASReceipt/sandboxReceipt")
            },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .unavailable
            }
        )

        #expect(await gate.isEntitled())
    }

    @Test("Mac App Store gate verifies production app transaction bundle ID")
    func macAppStoreGateVerifiesProductionAppTransactionBundleID() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            receiptURL: {
                URL(fileURLWithPath: "/Applications/Luxel.app/Contents/_MASReceipt/receipt")
            },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .verified(bundleID: "com.rawcontext.luxel")
            }
        )

        #expect(await gate.isEntitled())
    }

    @Test("Mac App Store gate rejects verified app transaction for another bundle ID")
    func macAppStoreGateRejectsMismatchedProductionAppTransactionBundleID() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            receiptURL: {
                URL(fileURLWithPath: "/Applications/Luxel.app/Contents/_MASReceipt/receipt")
            },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .verified(bundleID: "media.other.app")
            }
        )

        #expect(await !gate.isEntitled())
    }

    @Test("Mac App Store gate does not lock out on unavailable app transaction")
    func macAppStoreGateAllowsUnavailableAppTransaction() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            receiptURL: {
                URL(fileURLWithPath: "/Applications/Luxel.app/Contents/_MASReceipt/receipt")
            },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .unavailable
            }
        )

        #expect(await gate.isEntitled())
    }
}

private struct StubPurchaseGate: PurchaseGate {
    let isEntitled: Bool
    let changes: [Bool]

    init(isEntitled: Bool = true, changes: [Bool] = []) {
        self.isEntitled = isEntitled
        self.changes = changes
    }

    func isEntitled() async -> Bool {
        isEntitled
    }

    func entitlementChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            for change in changes {
                continuation.yield(change)
            }
            continuation.finish()
        }
    }
}
