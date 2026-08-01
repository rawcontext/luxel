import Foundation

public struct CaptionSidecarPersistenceService: Sendable {
    private let store: RecordingBundleSidecarStore

    public init(fileSystem: any FileSystem) {
        store = RecordingBundleSidecarStore(fileSystem: fileSystem)
    }

    public func save(_ track: CaptionTrack, in bundle: RecordingBundle) throws -> RecordingBundle {
        try store.save(CaptionSidecarDocument(track: track), kind: .captions, in: bundle)
    }

    public func load(from bundle: RecordingBundle) throws -> CaptionTrack? {
        try store.load(CaptionSidecarDocument.self, kind: .captions, from: bundle)?.track
    }
}
