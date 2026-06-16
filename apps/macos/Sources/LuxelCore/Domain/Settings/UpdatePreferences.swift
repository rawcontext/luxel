import Foundation

public struct UpdatePreferences: Codable, Equatable, Sendable {
    public static let defaults = UpdatePreferences()

    public var automaticallyCheckForUpdates: Bool
    public var automaticallyDownloadAndInstall: Bool
    public var channel: UpdateChannel

    public init(
        automaticallyCheckForUpdates: Bool = true,
        automaticallyDownloadAndInstall: Bool = false,
        channel: UpdateChannel = .stable
    ) {
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.automaticallyDownloadAndInstall = automaticallyDownloadAndInstall
        self.channel = channel
    }
}

public enum UpdateChannel: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
    case stable
    case beta

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .stable:
            "Stable"
        case .beta:
            "Beta"
        }
    }
}
