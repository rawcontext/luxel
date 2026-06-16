public struct AppMetadata: Equatable, Sendable {
    public let displayName: String
    public let version: String
    public let build: String
    public let copyright: String

    public init(
        displayName: String,
        version: String,
        build: String,
        copyright: String
    ) {
        self.displayName = displayName
        self.version = version
        self.build = build
        self.copyright = copyright
    }

    public var versionSummary: String {
        guard !build.isEmpty else {
            return version
        }

        return "\(version) (\(build))"
    }
}
