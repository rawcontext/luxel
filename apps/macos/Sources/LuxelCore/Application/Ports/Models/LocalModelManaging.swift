import Foundation

public protocol LocalModelManaging: Sendable {
    func descriptors() async -> [LocalModelDescriptor]
    func state(for id: LocalModelID) async -> LocalModelInstallationState
    func stateChanges() async -> AsyncStream<LocalModelStateChange>

    func install(_ id: LocalModelID) async throws -> LocalModelInstallation
    func cancelInstallation(_ id: LocalModelID) async
    func remove(_ id: LocalModelID) async throws

    func acquire(_ id: LocalModelID) async throws -> LocalModelLease
    func release(_ lease: LocalModelLease) async
    func reportInvalid(
        _ lease: LocalModelLease,
        reason: LocalModelRuntimeInvalidation
    ) async
}
