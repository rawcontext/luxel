import Foundation
import LuxelCore

enum LuxelCompositionRoot {
    static var appMetadata: AppMetadata {
        BundleAppMetadataReader().read()
    }

    static var defaultSettings: AppSettings {
        AppSettings.defaults(recordingsDirectory: defaultRecordingsDirectory)
    }

    static func settingsStore() -> any SettingsStore {
        UserDefaultsSettingsStore(defaultSettings: defaultSettings)
    }

    static func recordingHistoryService() -> RecordingHistoryService {
        RecordingHistoryService(
            store: recordingHistoryStore(),
            fileSystem: LocalFileSystem(),
            dateProvider: SystemDateProvider(),
            mediaProbe: AVFoundationMediaMetadataReader(),
            diagnosticClient: JSONRecordingDiagnosticClient(fileURL: recordingDiagnosticsFileURL)
        )
    }

    static func recordingHistoryStore() -> any RecordingHistoryStore {
        do {
            return try JSONRecordingHistoryStore(fileURL: recordingHistoryFileURL)
        } catch {
            return InMemoryRecordingHistoryStore()
        }
    }

    static func captureRecorder() -> any CaptureRecorder {
        ScreenCaptureKitRecorder()
    }

    static func audioRecorder() -> any AudioRecorder {
        AVFoundationAudioOnlyRecorder()
    }

    static func purchaseGateService() -> PurchaseGateService {
        PurchaseGateService(gate: AlwaysEntitledPurchaseGate())
    }

    @MainActor
    static func quickExportService(fileWorkflowService: ExportedFileWorkflowService) -> QuickExportService {
        QuickExportService(
            metadataReader: AVFoundationMediaMetadataReader(),
            exportService: ExportService(
                exporter: NativeMediaExporter(),
                fileSystem: LocalFileSystem()
            ),
            fileWorkflowService: fileWorkflowService,
            userNotifier: UserNotificationsNotifier()
        )
    }

    @MainActor
    static func screenshotCaptureService(history: RecordingHistoryService) -> ScreenshotCaptureService {
        ScreenshotCaptureService(
            capturer: ScreenCaptureKitStillCapturer(),
            fileWriter: LocalScreenshotFileWriter(),
            destinationClient: AppKitScreenshotDestinationClient(),
            history: history
        )
    }

    static var defaultRecordingsDirectory: URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

    private static var recordingHistoryFileURL: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "recording-history.json")
    }

    private static var recordingDiagnosticsFileURL: URL {
        applicationSupportDirectory
            .appending(path: "Luxel")
            .appending(path: "corrupt-recordings.jsonl")
    }

    private static var applicationSupportDirectory: URL {
        let applicationSupportDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return applicationSupportDirectory
    }
}
