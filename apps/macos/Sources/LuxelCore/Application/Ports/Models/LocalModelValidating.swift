import Foundation

public struct LocalModelPreparedPayload: Equatable, Sendable {
    public let payloadRoot: URL

    public init(payloadRoot: URL) {
        self.payloadRoot = payloadRoot
    }
}

public protocol LocalModelValidating: Sendable {
    var key: LocalModelValidatorKey { get }
    var version: Int { get }

    func prepareAndValidate(
        release: LocalModelRelease,
        stagedPayload: URL,
        preparedOutput: URL
    ) async throws -> LocalModelPreparedPayload
}

public protocol LocalModelCatalogProviding: Sendable {
    func catalog() throws -> LocalModelCatalog
}

public protocol LocalModelArtifactVerifying: Sendable {
    func verify(fileAt url: URL, artifact: LocalModelArtifact) throws
}

public struct LocalModelStagingArea: Equatable, Sendable {
    public let operationID: UUID
    public let sourceRoot: URL
    public let preparedRoot: URL

    public init(operationID: UUID, sourceRoot: URL, preparedRoot: URL) {
        self.operationID = operationID
        self.sourceRoot = sourceRoot
        self.preparedRoot = preparedRoot
    }
}

public protocol LocalModelRepository: Sendable {
    func reconcile(
        descriptor: LocalModelDescriptor,
        validatorVersion: Int
    ) throws -> LocalModelInstallation?
    func beginStaging(for id: LocalModelID) throws -> LocalModelStagingArea
    func artifactURL(_ artifact: LocalModelArtifact, in staging: LocalModelStagingArea) throws -> URL
    func validateExactSourceFiles(
        release: LocalModelRelease,
        staging: LocalModelStagingArea
    ) throws
    func promote(
        descriptor: LocalModelDescriptor,
        staging: LocalModelStagingArea,
        prepared: LocalModelPreparedPayload,
        validatorVersion: Int
    ) throws -> LocalModelInstallation
    func discard(_ staging: LocalModelStagingArea)
    func remove(_ installation: LocalModelInstallation) throws
    func availableCapacity() throws -> Int64
}
