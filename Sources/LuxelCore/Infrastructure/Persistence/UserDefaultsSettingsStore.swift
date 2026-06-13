import Foundation

public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key: String
    private let defaultSettings: AppSettings

    public init(
        userDefaults: UserDefaults = .standard,
        key: String = "settings",
        defaultSettings: AppSettings
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.defaultSettings = defaultSettings
    }

    public func load() throws -> AppSettings {
        guard let data = userDefaults.data(forKey: key) else {
            return defaultSettings
        }

        return try JSONDecoder().decode(AppSettings.self, from: data)
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        userDefaults.set(data, forKey: key)
    }
}
