import Foundation

public protocol CommandLineToolInstaller: Sendable {
    var bundledToolURL: URL? { get }

    func install(destination: URL) throws -> URL
}
