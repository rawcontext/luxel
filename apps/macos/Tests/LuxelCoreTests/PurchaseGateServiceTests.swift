import Foundation
@testable import LuxelCore
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

    @Test("Mac App Store gate accepts an Apple-verified app purchase")
    func macAppStoreGateAcceptsVerifiedAppPurchase() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            isTestFlightBuild: { false },
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
            isTestFlightBuild: { false },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .verified(bundleID: "media.other.app")
            }
        )

        #expect(await !gate.isEntitled())
    }

    @Test("Mac App Store gate rejects unverified app transactions")
    func macAppStoreGateRejectsUnverifiedAppTransaction() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            isTestFlightBuild: { false },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .unverified
            }
        )

        #expect(await !gate.isEntitled())
    }

    @Test("Mac App Store gate fails closed when Apple verification is unavailable")
    func macAppStoreGateRejectsUnavailableAppTransaction() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            isTestFlightBuild: { false },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .unavailable
            }
        )

        #expect(await !gate.isEntitled())
    }

    @Test("Mac App Store gate allows an Apple-signed TestFlight build without a purchase")
    func macAppStoreGateAllowsTestFlightBuildWithoutPurchase() async {
        let gate = MacAppStorePaidAppPurchaseGate(
            isTestFlightBuild: { true },
            currentBundleID: {
                "com.rawcontext.luxel"
            },
            appTransactionEntitlement: {
                .unavailable
            }
        )

        #expect(await gate.isEntitled())
    }

    @Test("TestFlight detection uses Apple's TestFlight certificate chain")
    func testFlightDetectionUsesTestFlightCertificateChain() {
        let requirement = MacAppStorePaidAppPurchaseGate.testFlightCodeRequirement

        #expect(requirement.contains("1.2.840.113635.100.6.2.1"))
        #expect(requirement.contains("1.2.840.113635.100.6.1.25.1"))
        #expect(!requirement.contains("1.2.840.113635.100.6.1.9"))
    }

    @Test("TestFlight detection rejects a non-TestFlight app")
    func testFlightDetectionRejectsNonTestFlightApp() {
        #expect(
            !MacAppStorePaidAppPurchaseGate.isTestFlightBuild(
                appBundleURL: Bundle.main.bundleURL
            )
        )
    }

    @Test("purchase gate locates an enclosing app bundle")
    func purchaseGateLocatesEnclosingAppBundle() {
        let executableURL = URL(
            fileURLWithPath: "/Applications/Luxel.app/Contents/MacOS/Luxel"
        )

        #expect(
            MacAppStorePaidAppPurchaseGate.enclosingAppBundleURL(
                containing: executableURL
            )?.path == "/Applications/Luxel.app"
        )
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
