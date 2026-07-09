import Foundation

public struct KnownSpeakerLibrary: Equatable, Sendable {
    public let profiles: [KnownSpeakerProfile]
    public let revision: String

    public init(profiles: [KnownSpeakerProfile], revision: String) {
        self.profiles = profiles
        self.revision = revision
    }

    public static let empty = KnownSpeakerLibrary(profiles: [], revision: "0")
}

public protocol KnownSpeakerProfileStore: Sendable {
    func library() throws -> KnownSpeakerLibrary
    @discardableResult
    func save(_ profile: KnownSpeakerProfile) throws -> KnownSpeakerLibrary
    @discardableResult
    func deleteProfile(id: UUID) throws -> KnownSpeakerLibrary
    /// Copies the clip audio into library-owned storage and returns the stored clip.
    func importExampleClip(
        from audioURL: URL,
        duration: TimeInterval,
        sourceRecordingURL: URL?
    ) throws -> KnownSpeakerExampleClip
    func removeExampleClipFile(_ clip: KnownSpeakerExampleClip) throws
}
