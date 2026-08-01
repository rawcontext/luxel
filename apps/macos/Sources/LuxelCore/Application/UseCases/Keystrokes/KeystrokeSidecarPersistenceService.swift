import Foundation

public struct KeystrokeSidecarPersistenceService: Sendable {
    private let store: RecordingBundleSidecarStore

    public init(fileSystem: any FileSystem) {
        store = RecordingBundleSidecarStore(fileSystem: fileSystem)
    }

    public func save(_ timeline: KeystrokeTimeline, in bundle: RecordingBundle) throws
    -> RecordingBundle {
        try store.save(KeystrokeSidecarDocument(timeline: timeline), kind: .keystrokes, in: bundle)
    }

    public func load(from bundle: RecordingBundle) throws -> KeystrokeTimeline? {
        try store.load(KeystrokeSidecarDocument.self, kind: .keystrokes, from: bundle)?.timeline
    }
}
