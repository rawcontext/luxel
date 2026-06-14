public struct PurchaseGateService: Sendable {
    private let gate: any PurchaseGate

    public init(gate: any PurchaseGate) {
        self.gate = gate
    }

    public func isEntitled() async -> Bool {
        await gate.isEntitled()
    }

    public func entitlementChanges() -> AsyncStream<Bool> {
        gate.entitlementChanges()
    }
}
