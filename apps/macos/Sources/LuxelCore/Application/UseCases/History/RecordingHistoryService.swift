import Foundation

public final class RecordingHistoryService: Sendable {
    let organizationLock = NSRecursiveLock()
    let store: any RecordingHistoryStore
    private let fileSystem: any FileSystem
    private let dateProvider: any DateProvider
    private let mediaProbe: any MediaProbe
    private let diagnosticClient: any RecordingDiagnosticClient
    private let corruptRecordingClassifier: CorruptRecordingClassifier
    private let calendar: Calendar

    public init(
        store: any RecordingHistoryStore,
        fileSystem: any FileSystem,
        dateProvider: any DateProvider,
        mediaProbe: any MediaProbe,
        diagnosticClient: any RecordingDiagnosticClient = NoopRecordingDiagnosticClient(),
        corruptRecordingClassifier: CorruptRecordingClassifier = CorruptRecordingClassifier(),
        calendar: Calendar = .current
    ) {
        self.store = store
        self.fileSystem = fileSystem
        self.dateProvider = dateProvider
        self.mediaProbe = mediaProbe
        self.diagnosticClient = diagnosticClient
        self.corruptRecordingClassifier = corruptRecordingClassifier
        self.calendar = calendar
    }

    public func getPastRecordings(matching filter: RecordingHistoryFilter = .all) -> [PastRecording] {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let validRecordings = store.recordings.compactMap { recording -> PastRecording? in
            guard recordingExists(recording) else {
                return nil
            }

            return recordingByDroppingMissingSidecars(
                recording.filteringExports { fileSystem.fileExists(at: $0.fileURL) }
            )
        }
        store.recordings = validRecordings
        return validRecordings.filter(filter.includes)
    }

    public func materializeRecordingBundle(
        rootURL: URL,
        primaryFileName: String = BundleManifest.defaultPrimaryFileName,
        sidecars: [BundleSidecarManifest]
    ) throws -> RecordingBundle {
        let manifest = try BundleManifest(
            primaryFileName: primaryFileName,
            sidecars: sidecars
        )
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)

        try fileSystem.createDirectory(at: rootURL)
        try persistManifest(manifest, for: rootURL)
        return bundle
    }

    @discardableResult
    public func addRecording(_ recording: PastRecording) -> [PastRecording] {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let recordings = [recording] + store.recordings
        let validRecordings = recordings.compactMap { recording -> PastRecording? in
            guard recordingExists(recording) else {
                return nil
            }

            return recordingByDroppingMissingSidecars(recording)
        }
        store.recordings = validRecordings
        return validRecordings
    }

    @discardableResult
    public func addReplayClip(fileURL: URL, name: String? = nil) -> PastRecording? {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let now = dateProvider.now()
        let replayName =
            name
            ?? RecordingName.timestamped(
                title: "Luxel Replay",
                now: now,
                calendar: calendar
            ).value
        let recording = PastRecording(
            fileURL: fileURL,
            name: replayName,
            date: now,
            kind: .recording
        )

        let recordings = addRecording(recording)
        return recordings.first == recording ? recording : nil
    }

    @discardableResult
    public func recordExport(
        _ exportedMedia: ExportedMedia,
        presetName: String? = nil,
        for recording: PastRecording
    ) -> [PastRecording] {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let validRecordings = getPastRecordings()

        guard fileSystem.fileExists(at: exportedMedia.fileURL),
            let recordingIndex = validRecordings.firstIndex(where: { $0.fileURL == recording.fileURL })
        else {
            return validRecordings
        }

        let export = RecordingExport(
            fileURL: exportedMedia.fileURL,
            format: exportedMedia.format,
            fileSizeBytes: exportedMedia.fileSizeBytes,
            date: dateProvider.now(),
            presetName: presetName
        )
        var updatedRecordings = validRecordings
        updatedRecordings[recordingIndex] = validRecordings[recordingIndex].addingExport(export)
        try? RecordingDocumentStore().recordExport(export, sourceURL: recording.primaryMediaURL)
        store.recordings = updatedRecordings
        return updatedRecordings
    }

    @discardableResult
    public func setCurrentRecording(
        fileURL: URL,
        name: String? = nil,
        options: RecordingOptions,
        bundleManifest: BundleManifest? = nil
    ) -> ActiveRecording {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let now = dateProvider.now()
        let recordingName = name ?? RecordingName.timestamped(now: now, calendar: calendar).value
        let recording = ActiveRecording(
            fileURL: fileURL,
            name: recordingName,
            date: now,
            options: options,
            bundleManifest: bundleManifest
        )
        store.activeRecording = recording
        return recording
    }

    @discardableResult
    public func stopCurrentRecording(
        finalFileURL: URL? = nil,
        recordingName: String? = nil
    ) -> PastRecording? {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        guard let activeRecording = store.activeRecording else {
            return nil
        }

        let recording = PastRecording(
            fileURL: finalFileURL ?? activeRecording.fileURL,
            name: recordingName ?? activeRecording.name,
            date: activeRecording.date,
            options: activeRecording.options,
            bundleManifest: activeRecording.bundleManifest
        )
        let sanitizedRecording = recordingByDroppingMissingSidecars(recording)
        addRecording(sanitizedRecording)
        store.activeRecording = nil
        return sanitizedRecording
    }

    public func clearCurrentRecording() {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        store.activeRecording = nil
    }

    public func cleanPastRecordings() throws {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let validRecordings = getPastRecordings()

        for recording in validRecordings {
            _ = try removeKeystrokeSidecar(for: recording)
            try fileSystem.removeFile(at: recording.fileURL)
        }

        store.recordings = []
    }

    @discardableResult
    public func discardRecording(_ recording: PastRecording) throws -> [PastRecording] {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let validRecordings = getPastRecordings()

        guard validRecordings.contains(where: { $0.fileURL == recording.fileURL }) else {
            return validRecordings
        }

        _ = try removeKeystrokeSidecar(for: recording)
        try fileSystem.trashItem(at: recording.fileURL)
        let remainingRecordings = validRecordings.filter { $0.fileURL != recording.fileURL }
        store.recordings = remainingRecordings
        return remainingRecordings
    }

    public func removeKeystrokeData(from recording: PastRecording) throws {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let updatedManifest = try removeKeystrokeSidecar(for: recording)
        guard let updatedManifest else {
            return
        }
        store.recordings = store.recordings.map { storedRecording in
            storedRecording.fileURL == recording.fileURL
                ? storedRecording.replacingBundleManifest(updatedManifest)
                : storedRecording
        }
    }

}

extension RecordingHistoryService {
    @discardableResult
    public func renameRecordingSource(
        from oldSourceURL: URL,
        to newSourceURL: URL
    ) throws -> [PastRecording] {
        organizationLock.lock()
        defer { organizationLock.unlock() }
        let oldSourceURL = oldSourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let newSourceURL = newSourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let renamedDisplayName = newSourceURL.deletingPathExtension().lastPathComponent
        var didRename = false

        let recordings = try store.recordings.map { recording in
            if recording.primaryMediaURL.standardizedFileURL.resolvingSymlinksInPath() == oldSourceURL,
                recording.bundleManifest?.organization != nil,
                let manifest = try RecordingDocumentStore().synchronizeUserRename(
                    from: oldSourceURL, to: newSourceURL) {
                didRename = true
                return recording.replacingFileURL(newSourceURL, name: renamedDisplayName, bundleManifest: manifest)
            }
            if recording.bundle == nil,
                recording.fileURL.standardizedFileURL.resolvingSymlinksInPath() == oldSourceURL {
                didRename = true
                return recording.replacingFileURL(newSourceURL, name: renamedDisplayName)
            }

            guard let bundle = recording.bundle,
                bundle.primaryURL.standardizedFileURL.resolvingSymlinksInPath() == oldSourceURL,
                newSourceURL.deletingLastPathComponent().standardizedFileURL
                    == bundle.rootURL.standardizedFileURL.resolvingSymlinksInPath()
            else {
                return recording
            }

            let manifest = try BundleManifest(
                schemaVersion: bundle.manifest.schemaVersion,
                primaryFileName: newSourceURL.lastPathComponent,
                sidecars: bundle.manifest.sidecars
            )
            try persistManifest(manifest, for: bundle.rootURL)
            didRename = true
            return recording.replacingFileURL(
                recording.fileURL,
                name: renamedDisplayName,
                bundleManifest: manifest
            )
        }

        if didRename {
            store.recordings = recordings.compactMap { recording in
                guard recordingExists(recording) else {
                    return nil
                }

                return recordingByDroppingMissingSidecars(recording)
            }
        }

        return getPastRecordings()
    }

}

extension RecordingHistoryService {
    @discardableResult
    public func recoverActiveRecording() async -> RecordingRecoveryResult {
        guard let activeRecording = store.activeRecording else {
            return .none
        }

        let result: RecordingRecoveryResult
        let mediaURL = activeRecording.primaryMediaURL
        switch await mediaProbe.inspectRecording(at: mediaURL) {
        case .playable:
            let recording = recordingByDroppingMissingSidecars(activeRecording.pastRecording)
            addRecording(recording)
            result = .playable(recording)
        case .corrupt(let reason):
            switch corruptRecordingClassifier.recoveryKind(for: reason) {
            case .knownRepairable:
                result = .knownCorrupt(fileURL: mediaURL, reason: reason)
            case .unknown:
                diagnosticClient.recordCorruptRecording(
                    CorruptRecordingDiagnostic(
                        fileURL: mediaURL,
                        reason: reason,
                        recordedAt: dateProvider.now()
                    ))
                result = .unknownCorrupt(fileURL: mediaURL, reason: reason)
            }
        }

        store.activeRecording = nil
        return result
    }
}

extension RecordingHistoryService {
    private func removeKeystrokeSidecar(for recording: PastRecording) throws -> BundleManifest? {
        try KeystrokeSidecarRemovalService(fileSystem: fileSystem, mode: .trash)
            .remove(nextTo: recording.primaryMediaURL, bundle: recording.bundle)
            .updatedBundleManifest
    }

    private func recordingExists(_ recording: PastRecording) -> Bool {
        guard fileSystem.fileExists(at: recording.fileURL) else {
            return false
        }

        if let bundle = recording.bundle {
            return fileSystem.fileExists(at: bundle.primaryURL)
        }

        return true
    }

    private func recordingByDroppingMissingSidecars(_ recording: PastRecording) -> PastRecording {
        guard let bundle = recording.bundle else {
            return recording
        }

        let existingSidecars = bundle.manifest.sidecars.filter { sidecar in
            let sidecarURL = bundle.rootURL.appendingPathComponent(sidecar.fileName)
            let exists = fileSystem.fileExists(at: sidecarURL)

            if !exists {
                recordMissingSidecar(at: sidecarURL)
            }

            return exists
        }

        guard existingSidecars != bundle.manifest.sidecars else {
            return recording
        }

        do {
            let manifest = try bundle.manifest.filteringSidecars { sidecar in
                existingSidecars.contains(sidecar)
            }
            try? persistManifest(manifest, for: bundle.rootURL)
            return recording.replacingBundleManifest(manifest)
        } catch {
            return recording
        }
    }

    private func recordMissingSidecar(at fileURL: URL) {
        diagnosticClient.recordCorruptRecording(
            CorruptRecordingDiagnostic(
                fileURL: fileURL,
                reason: "Missing bundle sidecar",
                recordedAt: dateProvider.now()
            ))
    }

    private func persistManifest(_ manifest: BundleManifest, for rootURL: URL) throws {
        let bundle = RecordingBundle(rootURL: rootURL, manifest: manifest)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try fileSystem.writeData(data, to: bundle.manifestURL)
    }
}
