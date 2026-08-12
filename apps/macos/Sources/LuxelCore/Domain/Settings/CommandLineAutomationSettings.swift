import Foundation

public struct CommandLinePairedClient: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let pairedAt: Date
    public var lastUsedAt: Date?

    public init(id: UUID, name: String, pairedAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.pairedAt = pairedAt
        self.lastUsedAt = lastUsedAt
    }
}

public struct CommandLineFolderGrant: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var directory: BookmarkedDirectory
    public let createdAt: Date

    public init(id: UUID = UUID(), directory: BookmarkedDirectory, createdAt: Date = Date()) {
        self.id = id
        self.directory = directory
        self.createdAt = createdAt
    }
}
