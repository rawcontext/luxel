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
