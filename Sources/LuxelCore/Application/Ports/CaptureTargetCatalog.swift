public protocol CaptureTargetCatalog: Sendable {
    func availableDisplays() async throws -> [DisplayBounds]
    func availableTargets() async throws -> [CaptureTargetOption]
    func refresh() async throws
}

public extension CaptureTargetCatalog {
    func refresh() async throws {
        _ = try await availableTargets()
    }
}
