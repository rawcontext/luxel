public protocol SettingsStore: Sendable {
    func load() throws -> AppSettings
    func save(_ settings: AppSettings) throws
}
