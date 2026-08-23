import Foundation
import LuxelCodecAV1
import LuxelCodecWebM
import LuxelCore
import LuxelPresentation

enum LuxelCompositionRoot {
    @MainActor
    static func errorReporter() -> any ErrorReporter {
        NoopErrorReporter()
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

    static func replayBufferService(
        settingsStore: any SettingsStore,
        exclusionRegistry: CaptureExclusionRegistry,
        systemActivityMonitor: any SystemActivityMonitor = AppKitSystemActivityMonitor()
    ) -> ReplayBufferService {
        ReplayBufferService(
            engine: replayBufferEngine(
                settingsStore: settingsStore,
                exclusionRegistry: exclusionRegistry
            ),
            systemActivityMonitor: systemActivityMonitor
        )
    }

    static func replayBufferClipService(
        replayBufferService: ReplayBufferService,
        history: RecordingHistoryService
    ) -> ReplayBufferClipService {
        ReplayBufferClipService(
            replayBufferService: replayBufferService,
            history: history
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
        exclusionRegistry: CaptureExclusionRegistry = CaptureExclusionRegistry(),
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)? = nil
    ) -> any CaptureRecorder {
        ScreenCaptureKitRecorder(
            contentFilterProvider: ShareableContentFilterProvider(exclusionRegistry: exclusionRegistry),
            audioLevelHandler: audioLevelHandler
        )
    }

    static func replayBufferEngine(
        settingsStore: any SettingsStore,
        exclusionRegistry: CaptureExclusionRegistry
    ) -> any ReplayBufferEngine {
        SegmentedSCStreamReplayEngine(
            contentFilterProvider: ShareableContentFilterProvider(exclusionRegistry: exclusionRegistry),
            storageDirectory: replayBufferCacheDirectory,
            clipDirectoryProvider: {
                ((try? settingsStore.load()) ?? defaultSettings).recordingsDirectory
            }
        )
    }

    static func audioRecorder(
        audioLevelHandler: (@Sendable (AudioLevelSample) -> Void)? = nil
    ) -> any AudioRecorder {
        ScreenCaptureKitAudioOnlyRecorder(audioLevelHandler: audioLevelHandler)
    }

    static func recordingOutputFinalizer() -> any RecordingOutputFinalizer {
        FileSystemRecordingOutputFinalizer(
            fileSystem: LocalFileSystem(),
            directoryAccessService: bookmarkedDirectoryAccessService()
        )
    }

    static func bookmarkedDirectoryAccessService() -> BookmarkedDirectoryAccessService {
        BookmarkedDirectoryAccessService(
            resolver: FoundationBookmarkedDirectoryResolver(),
            access: URLSecurityScopedResourceAccess()
        )
    }

    static func captureTargetCatalog() -> any CaptureTargetCatalog {
        CachedCaptureTargetCatalog(upstream: ScreenCaptureKitCaptureTargetCatalog())
    }

    static func captureTargetService(catalog: any CaptureTargetCatalog) -> CaptureTargetService {
        CaptureTargetService(catalog: catalog)
    }

    @MainActor
    static func cameraPreviewPanelController() -> CameraPreviewPanelController {
        let modelURL = Bundle.main.resourceURL?
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "modnet", directoryHint: .isDirectory)
            .appending(path: "MODNetPortraitMatting.mlmodelc", directoryHint: .isDirectory)
        return CameraPreviewPanelController {
            MODNetPortraitMattingProcessor(modelURL: modelURL)
        }
    }

    static func codecAdapterRegistry() -> CodecAdapterRegistry {
        do {
            return try CodecAdapterRegistry(registrations: [
                try AV1CodecAdapter.registration(),
                try WebMCodecAdapter.registration()
            ])
        } catch {
            return .empty
        }
    }

    @MainActor
    static func editorModel(
        codecAdapterRegistry: CodecAdapterRegistry = codecAdapterRegistry(),
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            exportService: ExportService(
                exporter: codecAdapterRegistry.mediaExporter(nativeExporter: NativeMediaExporter()),
                audioPreparer: exportAudioPreparer(),
                fileSystem: LocalFileSystem()
            ),
            exportSizeEstimationService: ExportSizeEstimationService(
                estimator: codecAdapterRegistry.exportSizeEstimator(
                    nativeEstimator: NativeExportSizeEstimator())
            ),
            audioTranscriptService: localAudioTranscriptService(),
            speakerNamingService: speakerVoiceNamingService(),
            speakerModelStore: speakerDiarizationModelStore,
            speechRecognitionAuthorizationService: AppleSpeechAuthorizationService(),
            codecAvailability: codecAdapterRegistry.availability,
            directoryAccessService: bookmarkedDirectoryAccessService(),
            errorReporter: errorReporter
        )
    }

    static let speakerDiarizationModelStore = FluidAudioSpeakerDiarizationModelStore(
        modelsDirectory: speakerDiarizationModelsDirectory,
        bundledModelDirectory: Bundle.main.resourceURL?
            .appending(path: "Models", directoryHint: .isDirectory)
            .appending(path: "speaker-diarization", directoryHint: .isDirectory)
    )

    @MainActor
    static func quickExportService(fileWorkflowService: ExportedFileWorkflowService)
        -> QuickExportService
    {
        let codecAdapterRegistry = codecAdapterRegistry()

        return QuickExportService(
            metadataReader: AVFoundationMediaMetadataReader(),
            exportService: ExportService(
                exporter: codecAdapterRegistry.mediaExporter(nativeExporter: NativeMediaExporter()),
                audioPreparer: exportAudioPreparer(),
                fileSystem: LocalFileSystem()
            ),
            fileWorkflowService: fileWorkflowService,
            directoryAccessService: bookmarkedDirectoryAccessService(),
            userNotifier: UserNotificationsNotifier()
        )
    }

    static var defaultRecordingsDirectory: URL {
        AppSettings.defaultRecordingsDirectory
    }

    static func exportAudioPreparer() -> ExportAudioPreparationService {
        ExportAudioPreparationService(
            enhancer: DeepFilterNetStudioVoiceEnhancer(
                locator: BundledStudioVoiceModelLocator(
                    modelDirectoryURL: Bundle.main.resourceURL?
                        .appending(path: "Models", directoryHint: .isDirectory)
                        .appending(path: "studio-voice", directoryHint: .isDirectory)
                )
            )
        )
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

    private static var replayBufferCacheDirectory: URL {
        cachesDirectory
            .appending(path: "Luxel")
            .appending(path: "ReplayBuffer", directoryHint: .isDirectory)
    }

    static var applicationSupportDirectory: URL {
        let applicationSupportDirectory =
            FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Application Support")

        return applicationSupportDirectory
    }

    private static var cachesDirectory: URL {
        let cachesDirectory =
            FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Library/Caches")

        return cachesDirectory
    }
}
