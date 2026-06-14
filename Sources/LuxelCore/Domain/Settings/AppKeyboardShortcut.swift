import Foundation

public enum AppKeyboardShortcutModifier: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
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
}

public struct AppKeyboardShortcut: Codable, Equatable, Identifiable, Sendable {
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
        let parts = rawValue
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let key = parts.last else {
            return nil
        }

        let modifiers = parts.dropLast().compactMap(AppKeyboardShortcutModifier.init(rawValue:))
        guard modifiers.count == parts.dropLast().count,
              let shortcut = try? AppKeyboardShortcut(key: key, modifiers: modifiers) else {
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

    public static let captureScreenshot: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+s")
    ].compactMap { $0 }

    public static let screenshotActiveWindow: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+w")
    ].compactMap { $0 }

    public static let screenshotFullscreen: [AppKeyboardShortcut] = [
        AppKeyboardShortcut(rawValue: "command+control+option+f")
    ].compactMap { $0 }
}

public enum AppKeyboardShortcutError: Error, Equatable {
    case invalidShortcut
}
