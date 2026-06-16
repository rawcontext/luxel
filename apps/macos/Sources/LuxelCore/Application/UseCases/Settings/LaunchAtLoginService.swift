public struct LaunchAtLoginService: Sendable {
    private let client: any LaunchAtLoginClient

    public init(client: any LaunchAtLoginClient) {
        self.client = client
    }

    public func isEnabled() -> Bool {
        client.isEnabled()
    }

    public func setEnabled(_ enabled: Bool) throws {
        try client.setEnabled(enabled)
    }
}
