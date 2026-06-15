public protocol AppMetadataReader: Sendable {
    func read() -> AppMetadata
}
