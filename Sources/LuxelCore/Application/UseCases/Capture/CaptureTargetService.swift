public struct CaptureTargetService: Sendable {
    private let catalog: any CaptureTargetCatalog

    public init(catalog: any CaptureTargetCatalog) {
        self.catalog = catalog
    }

    public func availableDisplays() async throws -> [DisplayBounds] {
        try await catalog.availableDisplays()
    }

    public func availableTargets() async throws -> [CaptureTargetOption] {
        try await catalog.availableTargets()
    }

    public func refresh() async throws {
        try await catalog.refresh()
    }
}
