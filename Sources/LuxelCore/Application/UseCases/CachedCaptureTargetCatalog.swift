public struct CaptureTargetCatalogSnapshot: Equatable, Sendable {
    public let displays: [DisplayBounds]
    public let targets: [CaptureTargetOption]

    public init(displays: [DisplayBounds], targets: [CaptureTargetOption]) {
        self.displays = displays
        self.targets = targets
    }
}

public actor CachedCaptureTargetCatalog: CaptureTargetCatalog {
    private let upstream: any CaptureTargetCatalog
    private var snapshot: CaptureTargetCatalogSnapshot?

    public init(upstream: any CaptureTargetCatalog) {
        self.upstream = upstream
    }

    public func availableDisplays() async throws -> [DisplayBounds] {
        if let snapshot {
            return snapshot.displays
        }

        return try await refreshSnapshot().displays
    }

    public func availableTargets() async throws -> [CaptureTargetOption] {
        if let snapshot {
            return snapshot.targets
        }

        return try await refreshSnapshot().targets
    }

    public func refresh() async throws {
        _ = try await refreshSnapshot()
    }

    private func refreshSnapshot() async throws -> CaptureTargetCatalogSnapshot {
        let snapshot = try await upstream.snapshot()
        self.snapshot = snapshot
        return snapshot
    }
}
