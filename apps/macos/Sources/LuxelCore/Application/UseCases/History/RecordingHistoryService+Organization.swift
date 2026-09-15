import Foundation

extension RecordingHistoryService {
    public func getCurrentRecording() -> ActiveRecording? {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        return store.activeRecording
    }

    public func replaceRecording(_ recording: PastRecording, previousURL: URL) {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let id = recording.bundleManifest?.organization?.id
        store.recordings = store.recordings.map {
            let sameID = id != nil && $0.bundleManifest?.organization?.id == id
            let sameURL = $0.fileURL.resolvingSymlinksInPath() == previousURL.resolvingSymlinksInPath()
            return sameID || sameURL ? recording : $0
        }
    }

    public func recording(withID id: UUID) -> PastRecording? {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        return store.recordings.first { $0.bundleManifest?.organization?.id == id }
    }

    public func refreshOrganizedRecordings(in root: URL) {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let discovered = RecordingDocumentStore().recordings(in: root)
        let byID = Dictionary(
            discovered.map { ($0.bundleManifest!.organization!.id, $0) }, uniquingKeysWith: { old, _ in old })
        let existingIDs = Set(store.recordings.compactMap { $0.bundleManifest?.organization?.id })
        let updated = store.recordings.map { recording in
            guard let id = recording.bundleManifest?.organization?.id, let found = byID[id] else { return recording }
            return PastRecording(
                fileURL: found.fileURL, name: found.name, date: recording.date,
                kind: recording.kind, options: recording.options,
                exports: found.exports
                    + recording.exports.filter {
                        !$0.fileURL.standardizedFileURL.path.hasPrefix(
                            recording.primaryMediaURL.deletingLastPathComponent().path + "/")
                    },
                bundleManifest: found.bundleManifest
            )
        }
        store.recordings = (updated + discovered.filter { !existingIDs.contains($0.bundleManifest!.organization!.id) })
            .sorted { $0.date > $1.date }
    }

    public func setFavorite(_ isFavorite: Bool, for recording: PastRecording) throws {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        guard
            let manifest = try RecordingDocumentStore().update(
                nextTo: recording.primaryMediaURL,
                {
                    $0.isFavorite = isFavorite
                })
        else { return }
        replaceRecording(recording.replacingBundleManifest(manifest), previousURL: recording.fileURL)
    }
}
