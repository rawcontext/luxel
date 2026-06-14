import Foundation

public struct NotchSurfaceSettings: Codable, Equatable, Sendable {
    public static let defaults = try! NotchSurfaceSettings()

    public let isEnabled: Bool
    public let idleHoverActionsEnabled: Bool
    public let showsWaveform: Bool
    public let autoCollapseSeconds: TimeInterval
    public let showsRecentShelf: Bool
    public let fallbackToFloatingHUDWhenUnavailable: Bool

    public var surfacePreferences: NotchSurfacePreferences {
        NotchSurfacePreferences(
            isEnabled: isEnabled,
            fallbackToFloatingHUDWhenUnavailable: fallbackToFloatingHUDWhenUnavailable
        )
    }

    public init(
        isEnabled: Bool = true,
        idleHoverActionsEnabled: Bool = true,
        showsWaveform: Bool = true,
        autoCollapseSeconds: TimeInterval = 6,
        showsRecentShelf: Bool = true,
        fallbackToFloatingHUDWhenUnavailable: Bool = true
    ) throws {
        guard autoCollapseSeconds.isFinite, autoCollapseSeconds >= 0 else {
            throw NotchSurfaceSettingsError.invalidAutoCollapseSeconds
        }

        self.isEnabled = isEnabled
        self.idleHoverActionsEnabled = idleHoverActionsEnabled
        self.showsWaveform = showsWaveform
        self.autoCollapseSeconds = autoCollapseSeconds
        self.showsRecentShelf = showsRecentShelf
        self.fallbackToFloatingHUDWhenUnavailable = fallbackToFloatingHUDWhenUnavailable
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case idleHoverActionsEnabled
        case showsWaveform
        case autoCollapseSeconds
        case showsRecentShelf
        case fallbackToFloatingHUDWhenUnavailable
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        try self.init(
            isEnabled: container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            idleHoverActionsEnabled: container.decodeIfPresent(
                Bool.self,
                forKey: .idleHoverActionsEnabled
            ) ?? true,
            showsWaveform: container.decodeIfPresent(Bool.self, forKey: .showsWaveform) ?? true,
            autoCollapseSeconds: container.decodeIfPresent(
                TimeInterval.self,
                forKey: .autoCollapseSeconds
            ) ?? 6,
            showsRecentShelf: container.decodeIfPresent(Bool.self, forKey: .showsRecentShelf) ?? true,
            fallbackToFloatingHUDWhenUnavailable: container.decodeIfPresent(
                Bool.self,
                forKey: .fallbackToFloatingHUDWhenUnavailable
            ) ?? true
        )
    }
}

public enum NotchSurfaceSettingsError: Error, Equatable {
    case invalidAutoCollapseSeconds
}
