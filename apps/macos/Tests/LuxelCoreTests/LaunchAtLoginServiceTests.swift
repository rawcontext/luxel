import LuxelCore
import Testing

@Suite("Launch at login service")
struct LaunchAtLoginServiceTests {
    @Test("service reads launch state")
    func serviceReadsLaunchState() {
        let client = StubLaunchAtLoginClient(enabled: true)
        let service = LaunchAtLoginService(client: client)

        #expect(service.isEnabled())
    }

    @Test("service updates launch state")
    func serviceUpdatesLaunchState() throws {
        let client = StubLaunchAtLoginClient(enabled: false)
        let service = LaunchAtLoginService(client: client)

        try service.setEnabled(true)

        #expect(client.enabled)
    }
}

private final class StubLaunchAtLoginClient: LaunchAtLoginClient, @unchecked Sendable {
    var enabled: Bool

    init(enabled: Bool) {
        self.enabled = enabled
    }

    func isEnabled() -> Bool {
        enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}
