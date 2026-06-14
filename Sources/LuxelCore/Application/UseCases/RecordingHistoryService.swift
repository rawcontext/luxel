import Foundation

public final class RecordingHistoryService: Sendable {
    private let store: any RecordingHistoryStore
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

    public func getCurrentRecording() -> ActiveRecording? {
        store.activeRecording
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
    public func addScreenshot(fileURL: URL, name: String? = nil) -> PastRecording? {
        let now = dateProvider.now()
        let screenshotName = name ?? RecordingName.timestamped(now: now, calendar: calendar).value
        let screenshot = PastRecording(
            fileURL: fileURL,
            name: screenshotName,
            date: now,
            kind: .screenshot
        )

        let recordings = addRecording(screenshot)
        return recordings.first == screenshot ? screenshot : nil
    }

    @discardableResult
    public func recordExport(
        _ exportedMedia: ExportedMedia,
        presetName: String? = nil,
        for recording: PastRecording
    ) -> [PastRecording] {
        let validRecordings = getPastRecordings()

        guard fileSystem.fileExists(at: exportedMedia.fileURL),
              let recordingIndex = validRecordings.firstIndex(where: { $0.fileURL == recording.fileURL }) else {
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
        guard let activeRecording = store.activeRecording else {
            return nil
        }

        let recording = PastRecording(
            fileURL: finalFileURL ?? activeRecording.fileURL,
            name: recordingName ?? activeRecording.name,
            date: dateProvider.now(),
            options: activeRecording.options,
            bundleManifest: activeRecording.bundleManifest
        )
        let sanitizedRecording = recordingByDroppingMissingSidecars(recording)
        addRecording(sanitizedRecording)
        store.activeRecording = nil
        return sanitizedRecording
    }

    public func clearCurrentRecording() {
        store.activeRecording = nil
    }

    public func cleanPastRecordings() throws {
        let validRecordings = getPastRecordings()

        for recording in validRecordings {
            try fileSystem.removeFile(at: recording.fileURL)
        }

        store.recordings = []
    }

    @discardableResult
    public func discardRecording(_ recording: PastRecording) throws -> [PastRecording] {
        let validRecordings = getPastRecordings()

        guard validRecordings.contains(where: { $0.fileURL == recording.fileURL }) else {
            return validRecordings
        }

        try fileSystem.trashItem(at: recording.fileURL)
        let remainingRecordings = validRecordings.filter { $0.fileURL != recording.fileURL }
        store.recordings = remainingRecordings
        return remainingRecordings
    }

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
        case let .corrupt(reason):
            switch corruptRecordingClassifier.recoveryKind(for: reason) {
            case .knownRepairable:
                result = .knownCorrupt(fileURL: mediaURL, reason: reason)
            case .unknown:
                diagnosticClient.recordCorruptRecording(CorruptRecordingDiagnostic(
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
        diagnosticClient.recordCorruptRecording(CorruptRecordingDiagnostic(
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
