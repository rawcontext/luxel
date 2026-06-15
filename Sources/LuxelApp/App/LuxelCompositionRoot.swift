import Foundation
import LuxelCore
import LuxelPresentation

enum LuxelCompositionRoot {
    @MainActor
    static func errorReporter() -> any ErrorReporter {
        let reporter = LuxelCrashReporter.shared
        reporter.configure(appMetadata: appMetadata)
        return reporter
    }

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

    static func captureRecorder(
        exclusionRegistry: CaptureExclusionRegistry = CaptureExclusionRegistry()
    ) -> any CaptureRecorder {
        ScreenCaptureKitRecorder(
            contentFilterProvider: ShareableContentFilterProvider(exclusionRegistry: exclusionRegistry)
        )
    }

    static func audioRecorder() -> any AudioRecorder {
        AVFoundationAudioOnlyRecorder()
    }

    static func recordingOutputFinalizer() -> any RecordingOutputFinalizer {
        FileSystemRecordingOutputFinalizer(
            fileSystem: LocalFileSystem(),
            directoryAccessService: BookmarkedDirectoryAccessService(
                resolver: FoundationBookmarkedDirectoryResolver(),
                access: URLSecurityScopedResourceAccess()
            )
        )
    }

    static func captureTargetCatalog() -> any CaptureTargetCatalog {
        CachedCaptureTargetCatalog(upstream: ScreenCaptureKitCaptureTargetCatalog())
    }

    static func captureTargetService(catalog: any CaptureTargetCatalog) -> CaptureTargetService {
        CaptureTargetService(catalog: catalog)
    }

    static func purchaseGateService() -> PurchaseGateService {
        PurchaseGateService(gate: AlwaysEntitledPurchaseGate())
    }

    static func commandLineToolInstallService() -> CommandLineToolInstallService {
        CommandLineToolInstallService(
            installer: BundledCommandLineToolInstaller(),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    static func codecAdapterRegistry() -> CodecAdapterRegistry {
        .empty
    }

    @MainActor
    static func editorModel(
        codecAdapterRegistry: CodecAdapterRegistry = codecAdapterRegistry(),
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            exportService: ExportService(
                exporter: codecAdapterRegistry.mediaExporter(nativeExporter: NativeMediaExporter()),
                fileSystem: LocalFileSystem()
            ),
            exportSizeEstimationService: ExportSizeEstimationService(
                estimator: codecAdapterRegistry.exportSizeEstimator(nativeEstimator: NativeExportSizeEstimator())
            ),
            codecAvailability: codecAdapterRegistry.availability,
            errorReporter: errorReporter
        )
    }

    @MainActor
    static func quickExportService(fileWorkflowService: ExportedFileWorkflowService) -> QuickExportService {
        let codecAdapterRegistry = codecAdapterRegistry()

        return QuickExportService(
            metadataReader: AVFoundationMediaMetadataReader(),
            exportService: ExportService(
                exporter: codecAdapterRegistry.mediaExporter(nativeExporter: NativeMediaExporter()),
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

    static var recordingStagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appending(path: "Luxel", directoryHint: .isDirectory)
            .appending(path: "Recordings", directoryHint: .isDirectory)
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
