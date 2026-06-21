public protocol CaptureTargetCatalog: Sendable {
    func availableDisplays() async throws -> [DisplayBounds]
    func availableTargets() async throws -> [CaptureTargetOption]
    func snapshot() async throws -> CaptureTargetCatalogSnapshot
    func refresh() async throws
}

extension CaptureTargetCatalog {
    public func snapshot() async throws -> CaptureTargetCatalogSnapshot {
        let displays = try await availableDisplays()
        let targets = try await availableTargets()
        return CaptureTargetCatalogSnapshot(displays: displays, targets: targets)
    }

    public func refresh() async throws {
        _ = try await snapshot()
    }
}
