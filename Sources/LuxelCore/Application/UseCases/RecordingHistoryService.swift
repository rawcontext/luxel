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

    public func getPastRecordings() -> [PastRecording] {
        let validRecordings = store.recordings.compactMap { recording -> PastRecording? in
            guard fileSystem.fileExists(at: recording.fileURL) else {
                return nil
            }

            return recording.filteringExports { fileSystem.fileExists(at: $0.fileURL) }
        }
        store.recordings = validRecordings
        return validRecordings
    }

    public func getCurrentRecording() -> ActiveRecording? {
        store.activeRecording
    }

    @discardableResult
    public func addRecording(_ recording: PastRecording) -> [PastRecording] {
        let recordings = [recording] + store.recordings
        let validRecordings = recordings.filter { fileSystem.fileExists(at: $0.fileURL) }
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
        options: RecordingOptions
    ) -> ActiveRecording {
        let now = dateProvider.now()
        let recordingName = name ?? RecordingName.timestamped(now: now, calendar: calendar).value
        let recording = ActiveRecording(
            fileURL: fileURL,
            name: recordingName,
            date: now,
            options: options
        )
        store.activeRecording = recording
        return recording
    }

    @discardableResult
    public func stopCurrentRecording(recordingName: String? = nil) -> PastRecording? {
        guard let activeRecording = store.activeRecording else {
            return nil
        }

        let recording = PastRecording(
            fileURL: activeRecording.fileURL,
            name: recordingName ?? activeRecording.name,
            date: dateProvider.now(),
            options: activeRecording.options
        )
        addRecording(recording)
        store.activeRecording = nil
        return recording
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
        switch await mediaProbe.inspectRecording(at: activeRecording.fileURL) {
        case .playable:
            addRecording(activeRecording.pastRecording)
            result = .playable(activeRecording.pastRecording)
        case let .corrupt(reason):
            switch corruptRecordingClassifier.recoveryKind(for: reason) {
            case .knownRepairable:
                result = .knownCorrupt(fileURL: activeRecording.fileURL, reason: reason)
            case .unknown:
                diagnosticClient.recordCorruptRecording(CorruptRecordingDiagnostic(
                    fileURL: activeRecording.fileURL,
                    reason: reason,
                    recordedAt: dateProvider.now()
                ))
                result = .unknownCorrupt(fileURL: activeRecording.fileURL, reason: reason)
            }
        }

        store.activeRecording = nil
        return result
    }
}
