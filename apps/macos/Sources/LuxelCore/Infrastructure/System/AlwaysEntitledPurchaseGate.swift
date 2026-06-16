public struct AlwaysEntitledPurchaseGate: PurchaseGate {
    public init() {}

    public func isEntitled() async -> Bool {
        true
    }

    public func entitlementChanges() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            continuation.yield(true)
        }
    }
}
