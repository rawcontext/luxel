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
                == URL(fileURLWithPath: "/Users/example/bin/luxel")
        )
    }

    @Test("service installs to default destination")
    func serviceInstallsToDefaultDestination() throws {
        let installer = SpyCommandLineToolInstaller()
        let destination = URL(fileURLWithPath: "/Users/example/bin/luxel")
        let service = CommandLineToolInstallService(
            installer: installer,
            defaultDestination: destination
        )

        #expect(try service.installToDefaultLocation() == destination)
        #expect(installer.destinations == [destination])
    }

    @Test("bundled installer reports missing helper")
    func bundledInstallerReportsMissingHelper() {
        let installer = BundledCommandLineToolInstaller(helperURL: nil)

        #expect(throws: CommandLineToolInstallerError.missingHelper) {
            _ = try installer.install(destination: URL(fileURLWithPath: "/Users/example/bin/luxel"))
        }
    }
}

private final class SpyCommandLineToolInstaller: CommandLineToolInstaller, @unchecked Sendable {
    var destinations: [URL] = []

    func install(destination: URL) throws -> URL {
        destinations.append(destination)
        return destination
    }
}
