import Foundation
import LuxelCore
import Testing

@Suite("Command line tool install service")
struct CommandLineToolInstallServiceTests {
    @Test("default destination installs luxel under user bin")
    func defaultDestinationInstallsLuxelUnderUserBin() {
        let homeDirectory = URL(fileURLWithPath: "/Users/example", isDirectory: true)

        #expect(
            CommandLineToolInstallService.defaultDestination(homeDirectory: homeDirectory)
                == URL(fileURLWithPath: "/Users/example/.local/bin/luxel")
        )
    }

    @Test("service installs to default destination")
    func serviceInstallsToDefaultDestination() throws {
        let installer = SpyCommandLineToolInstaller()
        let destination = URL(fileURLWithPath: "/Users/example/.local/bin/luxel")
        let service = CommandLineToolInstallService(
            installer: installer,
            defaultDestination: destination
        )

        #expect(try service.installToDefaultLocation() == destination)
        #expect(installer.destinations == [destination])
    }

    @Test("bundled installer reports missing tool")
    func bundledInstallerReportsMissingTool() {
        let installer = BundledCommandLineToolInstaller(bundledToolURL: nil)

        #expect(throws: CommandLineToolInstallerError.missingTool) {
            _ = try installer.install(
                destination: URL(fileURLWithPath: "/Users/example/.local/bin/luxel")
            )
        }
    }

    @Test("bundled installer creates symlink to bundled CLI")
    func bundledInstallerCreatesSymlinkToBundledCLI() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundledToolURL = directory.appending(path: "luxel-cli")
        let destination =
            directory
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "luxel")
        try installFixture(bundledToolURL: bundledToolURL, destination: destination)
    }

    @Test("bundled installer creates manpage symlink under local share")
    func bundledInstallerCreatesManpageSymlinkUnderLocalShare() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundledToolURL = directory.appending(path: "Luxel.app/Contents/MacOS/luxel-cli")
        let bundledManPageURL = directory.appending(
            path: "Luxel.app/Contents/Resources/man/man1/luxel.1")
        let destination =
            directory
            .appending(path: ".local", directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "luxel")
        try installManPageFixture(
            bundledToolURL: bundledToolURL,
            bundledManPageURL: bundledManPageURL,
            destination: destination
        )
    }

    @Test("bundled installer maps bin install to sibling share man directory")
    func bundledInstallerMapsBinInstallToSiblingShareManDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundledToolURL = directory.appending(path: "luxel-cli")
        let bundledManPageURL = directory.appending(path: "luxel.1")
        let destination =
            directory
            .appending(path: "usr", directoryHint: .isDirectory)
            .appending(path: "local", directoryHint: .isDirectory)
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "luxel")
        try installManPageFixture(
            bundledToolURL: bundledToolURL,
            bundledManPageURL: bundledManPageURL,
            destination: destination
        )
    }

    @Test("bundled installer replaces stale symlink")
    func bundledInstallerReplacesStaleSymlink() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundledToolURL = directory.appending(path: "luxel-cli")
        let staleToolURL = directory.appending(path: "old-luxel-cli")
        let destination = directory.appending(path: "luxel")
        try FileManager.default.createSymbolicLink(
            at: destination,
            withDestinationURL: staleToolURL
        )
        try installFixture(bundledToolURL: bundledToolURL, destination: destination)
    }

    @Test("bundled installer refuses to replace directory")
    func bundledInstallerRefusesToReplaceDirectory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundledToolURL = directory.appending(path: "luxel-cli")
        let destination = directory.appending(path: "luxel", directoryHint: .isDirectory)
        try Data("#!/bin/sh\n".utf8).write(to: bundledToolURL)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let installer = BundledCommandLineToolInstaller(bundledToolURL: bundledToolURL)

        #expect(throws: CommandLineToolInstallerError.destinationIsDirectory(destination.path)) {
            _ = try installer.install(destination: destination)
        }
    }

    @Test("path setup command configures zsh")
    func pathSetupCommandConfiguresZsh() {
        let command = CommandLineToolInstallService.pathSetupCommand(
            forDirectory: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            shell: .zsh,
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        #expect(command.contains("mkdir -p '/Users/example/.local/bin'"))
        #expect(command.contains(#""$HOME/.zshrc""#))
        #expect(command.contains("export PATH=\"$HOME/.local/bin:$PATH\""))
        #expect(!command.contains("/bin/sh -c"))
        #expect(!command.contains(".zprofile"))
        #expect(!command.contains("case "))
    }

    private func installFixture(
        bundledToolURL: URL,
        bundledManPageURL: URL? = nil,
        destination: URL,
        manPageDestination: URL? = nil
    ) throws {
        try FileManager.default.createDirectory(
            at: bundledToolURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: bundledToolURL)
        if let bundledManPageURL {
            try FileManager.default.createDirectory(
                at: bundledManPageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(".Dd July 1, 2026\n".utf8).write(to: bundledManPageURL)
        }
        let installer = BundledCommandLineToolInstaller(
            bundledToolURL: bundledToolURL,
            bundledManPageURL: bundledManPageURL
        )

        #expect(try installer.install(destination: destination) == destination)
        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: destination.path)
                == bundledToolURL.path
        )
        if let bundledManPageURL, let manPageDestination {
            #expect(
                try FileManager.default.destinationOfSymbolicLink(atPath: manPageDestination.path)
                    == bundledManPageURL.path
            )
        }
    }

    private func manPageDestination(for toolDestination: URL) -> URL {
        toolDestination.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "share", directoryHint: .isDirectory)
            .appending(path: "man", directoryHint: .isDirectory)
            .appending(path: "man1", directoryHint: .isDirectory)
            .appending(path: "luxel.1")
    }

    private func installManPageFixture(
        bundledToolURL: URL,
        bundledManPageURL: URL,
        destination: URL
    ) throws {
        try installFixture(
            bundledToolURL: bundledToolURL,
            bundledManPageURL: bundledManPageURL,
            destination: destination,
            manPageDestination: manPageDestination(for: destination)
        )
    }

    @Test("path setup command configures bash")
    func pathSetupCommandConfiguresBash() {
        let command = CommandLineToolInstallService.pathSetupCommand(
            forDirectory: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            shell: .bash,
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        #expect(command.contains(#""$HOME/.bash_profile""#))
        #expect(command.contains("export PATH=\"$HOME/.local/bin:$PATH\""))
        #expect(!command.contains(".zshrc"))
    }

    @Test("path setup command configures fish")
    func pathSetupCommandConfiguresFish() {
        let command = CommandLineToolInstallService.pathSetupCommand(
            forDirectory: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            shell: .fish,
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        #expect(command.contains(#""$HOME/.config/fish/conf.d""#))
        #expect(command.contains(#""$HOME/.config/fish/conf.d/luxel.fish""#))
        #expect(command.contains("set -gx PATH \"$HOME/.local/bin\" $PATH"))
        #expect(!command.contains("export PATH="))
    }

    @Test("path setup command configures POSIX profile")
    func pathSetupCommandConfiguresPOSIXProfile() {
        let command = CommandLineToolInstallService.pathSetupCommand(
            forDirectory: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            shell: .posix,
            homeDirectory: URL(fileURLWithPath: "/Users/example", isDirectory: true)
        )

        #expect(command.contains(#""$HOME/.profile""#))
        #expect(command.contains("export PATH=\"$HOME/.local/bin:$PATH\""))
        #expect(!command.contains(".bash_profile"))
    }

    private func temporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "luxel-cli-install-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}

private final class SpyCommandLineToolInstaller: CommandLineToolInstaller, @unchecked Sendable {
    let bundledToolURL: URL? = URL(
        fileURLWithPath: "/Applications/Luxel.app/Contents/MacOS/luxel-cli")
    var destinations: [URL] = []

    func install(destination: URL) throws -> URL {
        destinations.append(destination)
        return destination
    }
}
