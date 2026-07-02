import Foundation

public struct CommandLineToolInstallService: Sendable {
    public let defaultDestination: URL
    private let installer: any CommandLineToolInstaller
    private let destinationPicker: (any CommandLineToolInstallDestinationPicker)?
    private let directoryAccessService: BookmarkedDirectoryAccessService?

    public init(
        installer: any CommandLineToolInstaller,
        defaultDestination: URL,
        destinationPicker: (any CommandLineToolInstallDestinationPicker)? = nil,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil
    ) {
        self.installer = installer
        self.defaultDestination = defaultDestination
        self.destinationPicker = destinationPicker
        self.directoryAccessService = directoryAccessService
    }

    public init(
        installer: any CommandLineToolInstaller,
        homeDirectory: URL,
        destinationPicker: (any CommandLineToolInstallDestinationPicker)? = nil,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil
    ) {
        self.init(
            installer: installer,
            defaultDestination: Self.defaultDestination(homeDirectory: homeDirectory),
            destinationPicker: destinationPicker,
            directoryAccessService: directoryAccessService
        )
    }

    public func installToDefaultLocation() throws -> URL {
        try installer.install(destination: defaultDestination)
    }

    @MainActor
    public func chooseAndInstall() throws -> CommandLineToolInstall? {
        guard let destinationPicker else {
            let linkURL = try installToDefaultLocation()
            return CommandLineToolInstall(
                linkURL: linkURL,
                directoryBookmark: BookmarkedDirectory(
                    url: linkURL.deletingLastPathComponent(),
                    bookmarkData: Data()
                )
            )
        }

        guard
            let directory = try destinationPicker.chooseInstallDirectory(
                defaultDirectory: defaultDestination.deletingLastPathComponent()
            )
        else {
            return nil
        }

        return try install(in: directory)
    }

    public func repairInstall(_ install: CommandLineToolInstall) throws -> CommandLineToolInstall {
        try self.install(in: install.directoryBookmark, linkName: install.linkURL.lastPathComponent)
    }

    public func pathSetupCommand(
        for install: CommandLineToolInstall,
        shell: CommandLineShell,
        homeDirectory: URL
    ) -> String {
        Self.pathSetupCommand(
            forDirectory: install.linkURL.deletingLastPathComponent(),
            shell: shell,
            homeDirectory: homeDirectory
        )
    }

    public static func defaultDestination(homeDirectory: URL) -> URL {
        homeDirectory
            .appending(path: ".local", directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "luxel")
    }

    public static func pathSetupCommand(
        forDirectory directory: URL,
        shell: CommandLineShell,
        homeDirectory: URL
    ) -> String {
        let pathLine: String
        let profilePath: String
        let setupDirectoryArguments: [String]

        switch shell {
        case .zsh:
            pathLine = posixPathSetupLine(for: directory, homeDirectory: homeDirectory)
            profilePath = #""$HOME/.zshrc""#
            setupDirectoryArguments = [shellQuote(directory.path)]
        case .bash:
            pathLine = posixPathSetupLine(for: directory, homeDirectory: homeDirectory)
            profilePath = #""$HOME/.bash_profile""#
            setupDirectoryArguments = [shellQuote(directory.path)]
        case .fish:
            pathLine = fishPathSetupLine(for: directory, homeDirectory: homeDirectory)
            profilePath = #""$HOME/.config/fish/conf.d/luxel.fish""#
            setupDirectoryArguments = [shellQuote(directory.path), #""$HOME/.config/fish/conf.d""#]
        case .posix:
            pathLine = posixPathSetupLine(for: directory, homeDirectory: homeDirectory)
            profilePath = #""$HOME/.profile""#
            setupDirectoryArguments = [shellQuote(directory.path)]
        }

        let mkdirArguments = setupDirectoryArguments.joined(separator: " ")

        return """
      mkdir -p \(mkdirArguments)
      grep -qxF \(shellQuote(pathLine)) \(profilePath) 2>/dev/null || echo \(shellQuote(pathLine)) >> \(profilePath)
      """
    }

    private func install(
        in directory: BookmarkedDirectory,
        linkName: String = "luxel"
    ) throws -> CommandLineToolInstall {
        if let directoryAccessService {
            let result = try directoryAccessService.withAccess(to: directory) { resolvedDirectory in
                try installer.install(
                    destination: resolvedDirectory.url.appending(path: linkName)
                )
            }

            guard let linkURL = result.value else {
                throw CommandLineToolInstallerError.installPermissionRevoked
            }

            return CommandLineToolInstall(
                linkURL: linkURL,
                directoryBookmark: result.directory
            )
        }

        let linkURL = try installer.install(destination: directory.url.appending(path: linkName))
        return CommandLineToolInstall(linkURL: linkURL, directoryBookmark: directory)
    }

    private static func shellDisplayPath(for directory: URL, homeDirectory: URL) -> String {
        let directoryPath = directory.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path

        if directoryPath == homePath {
            return "$HOME"
        }

        let homePrefix = homePath + "/"
        if directoryPath.hasPrefix(homePrefix) {
            return "$HOME/" + directoryPath.dropFirst(homePrefix.count)
        }

        return directoryPath
    }

    private static func posixPathSetupLine(for directory: URL, homeDirectory: URL) -> String {
        let path = shellDisplayPath(for: directory, homeDirectory: homeDirectory)
        return "export PATH=\"\(path):$PATH\""
    }

    private static func fishPathSetupLine(for directory: URL, homeDirectory: URL) -> String {
        let path = shellDisplayPath(for: directory, homeDirectory: homeDirectory)
        return "set -gx PATH \"\(path)\" $PATH"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
