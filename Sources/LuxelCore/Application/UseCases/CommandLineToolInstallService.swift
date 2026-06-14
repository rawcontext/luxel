import Foundation

public struct CommandLineToolInstallService: Sendable {
    public let defaultDestination: URL
    private let installer: any CommandLineToolInstaller

    public init(
        installer: any CommandLineToolInstaller,
        defaultDestination: URL
    ) {
        self.installer = installer
        self.defaultDestination = defaultDestination
    }

    public init(
        installer: any CommandLineToolInstaller,
        homeDirectory: URL
    ) {
        self.init(
            installer: installer,
            defaultDestination: Self.defaultDestination(homeDirectory: homeDirectory)
        )
    }

    public func installToDefaultLocation() throws -> URL {
        try installer.install(destination: defaultDestination)
    }

    public static func defaultDestination(homeDirectory: URL) -> URL {
        homeDirectory
            .appending(path: "bin", directoryHint: .isDirectory)
            .appending(path: "luxel")
    }
}
