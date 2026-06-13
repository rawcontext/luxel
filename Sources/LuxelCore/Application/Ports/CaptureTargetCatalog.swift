public protocol CaptureTargetCatalog: Sendable {
    func availableDisplays() async throws -> [DisplayBounds]
    func availableTargets() async throws -> [CaptureTargetOption]
}
