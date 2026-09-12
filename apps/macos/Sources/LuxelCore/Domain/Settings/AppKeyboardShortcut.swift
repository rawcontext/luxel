import Foundation

public enum AppKeyboardShortcutModifier: String, Codable, CaseIterable, Equatable, Hashable,
    Sendable {
    case command
    case control
    case option
    case shift

    public var displayName: String {
        switch self {
        case .command:
            "Command"
        case .control:
            "Control"
        case .option:
            "Option"
        case .shift:
            "Shift"
        }
    }

    public var displaySymbol: String {
        switch self {
        case .command:
            "\u{2318}"
        case .control:
            "\u{2303}"
        case .option:
            "\u{2325}"
        case .shift:
            "\u{21E7}"
        }
    }
}

public struct AppKeyboardShortcut: Codable, Equatable, Identifiable, Sendable {
    private static let displayModifierOrder: [AppKeyboardShortcutModifier] = [
        .control,
        .option,
        .shift,
        .command
    ]

    public let key: String
    public let modifiers: [AppKeyboardShortcutModifier]

    public init(key: String, modifiers: [AppKeyboardShortcutModifier]) throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uniqueModifiers = Array(Set(modifiers)).sorted { $0.rawValue < $1.rawValue }

        guard normalizedKey.count == 1, !uniqueModifiers.isEmpty else {
            throw AppKeyboardShortcutError.invalidShortcut
        }

        self.key = normalizedKey
        self.modifiers = uniqueModifiers
    }

    public init?(rawValue: String) {
        let parts =
            rawValue
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let key = parts.last else {
            return nil
        }

        let modifiers = parts.dropLast().compactMap(AppKeyboardShortcutModifier.init(rawValue:))
        guard modifiers.count == parts.dropLast().count,
            let shortcut = try? AppKeyboardShortcut(key: key, modifiers: modifiers)
        else {
            return nil
        }

        self = shortcut
    }

    public var id: String {
        rawValue
    }

    public var rawValue: String {
        (modifiers.map(\.rawValue) + [key]).joined(separator: "+")
    }

    public var displayName: String {
        (modifiers.map(\.displayName) + [key.uppercased()]).joined(separator: " ")
    }

    public var compactDisplayName: String {
        let orderedModifierSymbols = Self.displayModifierOrder.compactMap { modifier in
            modifiers.contains(modifier) ? modifier.displaySymbol : nil
        }

        return (orderedModifierSymbols + [key.uppercased()]).joined()
    }
}

public enum AppKeyboardShortcutPresets {
    public static let capture: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+r")
    ].compactMap { $0 }

    public static let toggleRecording: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+t")
    ].compactMap { $0 }

    public static let recordActiveWindow: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+shift+w")
    ].compactMap { $0 }

    public static let recordFullscreen: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+shift+f")
    ].compactMap { $0 }

    public static let audioOnlyRecording: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+a")
    ].compactMap { $0 }

    public static let quickRecordLast: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+q")
    ].compactMap { $0 }

    public static let clipReplayBuffer: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+c")
    ].compactMap { $0 }
}

public struct AppKeyboardShortcutConflict: Equatable, Sendable {
    public let shortcut: AppKeyboardShortcut
    public let systemAction: String

    public init(shortcut: AppKeyboardShortcut, systemAction: String) {
        self.shortcut = shortcut
        self.systemAction = systemAction
    }
}

public struct AppKeyboardShortcutConflictDetector: Sendable {
    public static let knownSystemConflicts: [AppKeyboardShortcutConflict] = [
        systemConflict("command+shift+3", action: "macOS full-screen capture"),
        systemConflict("command+shift+4", action: "macOS selection capture"),
        systemConflict("command+shift+5", action: "macOS capture controls"),
        systemConflict("command+shift+6", action: "macOS Touch Bar capture"),
        systemConflict("command+control+shift+3", action: "macOS full-screen capture to Clipboard"),
        systemConflict("command+control+shift+4", action: "macOS selection capture to Clipboard")
    ].compactMap(\.self)

    private let conflictsByShortcut: [String: AppKeyboardShortcutConflict]

    public init(systemConflicts: [AppKeyboardShortcutConflict] = Self.knownSystemConflicts) {
        conflictsByShortcut = Dictionary(
            uniqueKeysWithValues: systemConflicts.map { ($0.shortcut.rawValue, $0) }
        )
    }

    public func conflict(forRawValue rawValue: String) -> AppKeyboardShortcutConflict? {
        guard let shortcut = AppKeyboardShortcut(rawValue: rawValue) else {
            return nil
        }

        return conflict(for: shortcut)
    }

    public func conflict(for shortcut: AppKeyboardShortcut) -> AppKeyboardShortcutConflict? {
        conflictsByShortcut[shortcut.rawValue]
    }

    private static func systemConflict(
        _ rawValue: String,
        action: String
    ) -> AppKeyboardShortcutConflict? {
        guard let shortcut = AppKeyboardShortcut(rawValue: rawValue) else {
            return nil
        }

        return AppKeyboardShortcutConflict(shortcut: shortcut, systemAction: LuxelLocalization.string(action))
    }
}

public enum AppKeyboardShortcutError: Error, Equatable {
    case invalidShortcut
}
