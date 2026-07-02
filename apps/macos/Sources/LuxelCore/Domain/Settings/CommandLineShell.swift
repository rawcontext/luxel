import Foundation

public enum CommandLineShell: String, CaseIterable, Codable, Equatable, Identifiable, Sendable {
    case zsh
    case bash
    case fish
    case posix

    public static let allCases: [CommandLineShell] = [.zsh, .bash, .fish, .posix]

    public var id: Self {
        self
    }

    public var displayName: String {
        switch self {
        case .zsh:
            "zsh"
        case .bash:
            "bash"
        case .fish:
            "fish"
        case .posix:
            "POSIX sh"
        }
    }
}
