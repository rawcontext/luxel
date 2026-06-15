import Foundation

public protocol CommandLineToolInstaller: Sendable {
    func install(destination: URL) throws -> URL
}
