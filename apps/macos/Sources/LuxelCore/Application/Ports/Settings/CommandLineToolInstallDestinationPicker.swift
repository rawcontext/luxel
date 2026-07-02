import Foundation

@MainActor
public protocol CommandLineToolInstallDestinationPicker: AnyObject, Sendable {
    func chooseInstallDirectory(defaultDirectory: URL) throws -> BookmarkedDirectory?
}
