import ServiceManagement

public struct SMAppServiceLaunchAtLoginClient: LaunchAtLoginClient {
    public init() {}

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
