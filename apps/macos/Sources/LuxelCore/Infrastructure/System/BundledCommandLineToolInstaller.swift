import Foundation

public struct BundledCommandLineToolInstaller: CommandLineToolInstaller {
    public let bundledToolURL: URL?
    public let bundledManPageURL: URL?

    public init(bundle: Bundle = .main) {
        bundledToolURL =
            bundle.url(forAuxiliaryExecutable: "luxel-cli")
            ?? bundle.url(forResource: "luxel-cli", withExtension: nil)
        bundledManPageURL = bundle.url(
            forResource: "luxel",
            withExtension: "1",
            subdirectory: "man/man1"
        )
    }

    public init(bundledToolURL: URL?, bundledManPageURL: URL? = nil) {
        self.bundledToolURL = bundledToolURL
        self.bundledManPageURL = bundledManPageURL
    }

    public func install(destination: URL) throws -> URL {
        guard let bundledToolURL else {
            throw CommandLineToolInstallerError.missingTool
        }

        let fileManager = FileManager.default
        let directoryURL = destination.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        try replaceWithSymbolicLink(
            at: destination,
            target: bundledToolURL,
            fileManager: fileManager
        )

        if let bundledManPageURL {
            try installManPage(
                bundledManPageURL,
                commandDestination: destination,
                fileManager: fileManager
            )
        }

        return destination
    }

    private func installManPage(
        _ bundledManPageURL: URL,
        commandDestination: URL,
        fileManager: FileManager
    ) throws {
        let destination = manPageDestination(forCommandDestination: commandDestination)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try replaceWithSymbolicLink(
            at: destination,
            target: bundledManPageURL,
            fileManager: fileManager
        )
    }

    private func replaceWithSymbolicLink(
        at destination: URL,
        target: URL,
        fileManager: FileManager
    ) throws {
        if existingDestinationIsDirectory(destination, fileManager: fileManager) {
            throw CommandLineToolInstallerError.destinationIsDirectory(destination.path)
        }

        if existingDestinationCanBeReplaced(destination, fileManager: fileManager) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.createSymbolicLink(
            at: destination,
            withDestinationURL: target
        )
    }

    private func manPageDestination(forCommandDestination destination: URL) -> URL {
        let commandDirectory = destination.deletingLastPathComponent()
        let installRoot =
            commandDirectory.lastPathComponent == "bin"
            ? commandDirectory.deletingLastPathComponent()
            : commandDirectory

        return
            installRoot
            .appending(path: "share", directoryHint: .isDirectory)
            .appending(path: "man", directoryHint: .isDirectory)
            .appending(path: "man1", directoryHint: .isDirectory)
            .appending(path: "luxel.1")
    }

    private func existingDestinationIsDirectory(
        _ destination: URL,
        fileManager: FileManager
    ) -> Bool {
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue
    }

    private func existingDestinationCanBeReplaced(
        _ destination: URL,
        fileManager: FileManager
    ) -> Bool {
        if (try? fileManager.destinationOfSymbolicLink(atPath: destination.path)) != nil {
            return true
        }

        return fileManager.fileExists(atPath: destination.path)
    }
}

public enum CommandLineToolInstallerError: LocalizedError, Equatable {
    case missingTool
    case installPermissionRevoked
    case destinationIsDirectory(String)

    public var errorDescription: String? {
        switch self {
        case .missingTool:
            "The command-line tool is missing from this Luxel app bundle."
        case .installPermissionRevoked:
            "Luxel no longer has permission to update the command-line tool link. Choose the install location again."
        case .destinationIsDirectory(let path):
            "A folder already exists at \(path). Choose a different install folder or remove that folder first."
        }
    }
}
