public protocol PurchaseGate: Sendable {
    func isEntitled() async -> Bool
    func entitlementChanges() -> AsyncStream<Bool>
}
