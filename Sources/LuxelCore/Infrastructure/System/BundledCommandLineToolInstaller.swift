import Foundation

public struct BundledCommandLineToolInstaller: CommandLineToolInstaller {
    private let helperURL: URL?

    public init(bundle: Bundle = .main) {
        helperURL = bundle.url(forResource: "install-cli", withExtension: nil)
    }

    public init(helperURL: URL?) {
        self.helperURL = helperURL
    }

    public func install(destination: URL) throws -> URL {
        guard let helperURL else {
            throw CommandLineToolInstallerError.missingHelper
        }

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [destination.path]

        do {
            try process.run()
        } catch {
            throw CommandLineToolInstallerError.launchFailed(String(describing: error))
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw CommandLineToolInstallerError.installFailed(process.terminationStatus)
        }

        return destination
    }
}

public enum CommandLineToolInstallerError: LocalizedError, Equatable {
    case missingHelper
    case launchFailed(String)
    case installFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .missingHelper:
            "The command-line tool installer is missing from this Luxel app bundle."
        case .launchFailed(let message):
            "Could not launch the command-line tool installer: \(message)"
        case .installFailed(let status):
            "Command-line tool installation failed with exit status \(status)."
        }
    }
}
