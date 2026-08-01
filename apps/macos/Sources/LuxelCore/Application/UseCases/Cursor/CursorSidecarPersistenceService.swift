import Foundation

public struct CursorSidecarPersistenceService: Sendable {
    private let store: RecordingBundleSidecarStore

    public init(fileSystem: any FileSystem) {
        store = RecordingBundleSidecarStore(fileSystem: fileSystem)
    }

    public func save(_ timeline: CursorTimeline, in bundle: RecordingBundle) throws -> RecordingBundle {
        try store.save(CursorSidecarDocument(timeline: timeline), kind: .cursor, in: bundle)
    }

    public func load(from bundle: RecordingBundle) throws -> CursorTimeline? {
        try store.load(CursorSidecarDocument.self, kind: .cursor, from: bundle)?.timeline
    }
}
