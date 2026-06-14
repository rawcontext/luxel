import LuxelCore
import Observation

@MainActor
@Observable
final class LuxelMenuModel {
    var settings: AppSettings
    var launchAtLogin: Bool
    var screenRecordingStatus: PermissionStatus = .unknown
    var microphoneStatus: PermissionStatus = .unknown
    var cameraStatus: PermissionStatus = .unknown
    var audioLevelSample: AudioLevelSample = .silent
    var audioInputDevices: [AudioInputDeviceOption] = [.systemDefault]
    var cameraDevices: [CameraDeviceOption] = []
    var recentRecordings: [PastRecording] = []
    var recentRecordingFilter: RecordingHistoryFilter = .all
    var captureTargets: [CaptureTargetOption] = []
    var selectedCaptureTargetID: String?
    var captureTargetStatusMessage: String?
    var recordingState: RecordingMenuState = .idle
    var recordingNoticeMessage: String?
    var recordingActionErrorMessage: String?
    var quickExportStatusMessage: String?
    var quickExportProgress: QuickExportProgressPresentation?
    var recoveryState: RecordingRecoveryMenuState?
    var permissionPrompt: PermissionPrompt?
    var recoveryPrompt: RecoveryPrompt?
    var automationPrompt: AutomationURLPrompt?
    let appMetadata: AppMetadata

    @ObservationIgnored let settingsStore: any SettingsStore
    @ObservationIgnored let permissionClient: any PermissionClient
    @ObservationIgnored let launchAtLoginService: LaunchAtLoginService
    @ObservationIgnored let recordingHistoryService: RecordingHistoryService
    @ObservationIgnored let recordingLifecycleService: RecordingLifecycleService
    @ObservationIgnored let audioRecordingLifecycleService: AudioRecordingLifecycleService
    @ObservationIgnored let captureTargetService: CaptureTargetService
    @ObservationIgnored let captureExclusionRegistry: CaptureExclusionRegistry
    @ObservationIgnored let recordingFramePanelController: RecordingFramePanelController
    @ObservationIgnored let audioInputDeviceService: AudioInputDeviceService
    @ObservationIgnored let cameraDeviceService: CameraDeviceService
    @ObservationIgnored let cameraPreviewPanelController: CameraPreviewPanelController
    @ObservationIgnored let audioLevelMonitorFactory: () -> any AudioLevelMonitor
    @ObservationIgnored let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored let bookmarkedDirectoryPicker: any BookmarkedDirectoryPicker
    @ObservationIgnored let quickExportService: QuickExportService
    @ObservationIgnored var quickExportTask: Task<QuickExportResult, any Error>?
    @ObservationIgnored let screenshotCaptureService: ScreenshotCaptureService
    @ObservationIgnored let permissionGuidanceService: PermissionGuidanceService
    @ObservationIgnored let lastCaptureRecordingPlanner: LastCaptureRecordingPlanner
    @ObservationIgnored let screenshotCapturePlanner: ScreenshotCapturePlanner
    @ObservationIgnored let activeWindowCatalog: any ActiveWindowCatalog
    @ObservationIgnored let activeWindowCaptureTargetResolver: ActiveWindowCaptureTargetResolver
    @ObservationIgnored let pointerDisplayProvider: any PointerDisplayProvider
    @ObservationIgnored let fullscreenCaptureTargetResolver: FullscreenCaptureTargetResolver
    @ObservationIgnored let screenshotThumbnailPresenter: any ScreenshotThumbnailPresenter

    init(
        settingsStore: any SettingsStore = LuxelCompositionRoot.settingsStore(),
        permissionClient: any PermissionClient = ApplePermissionClient(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(
            client: SMAppServiceLaunchAtLoginClient()
        ),
        recordingHistoryService: RecordingHistoryService = LuxelCompositionRoot.recordingHistoryService(),
        captureTargetService: CaptureTargetService = CaptureTargetService(
            catalog: ScreenCaptureKitCaptureTargetCatalog()
        ),
        captureExclusionRegistry: CaptureExclusionRegistry = CaptureExclusionRegistry(),
        recordingFramePanelController: RecordingFramePanelController = RecordingFramePanelController(),
        audioInputDeviceService: AudioInputDeviceService = AudioInputDeviceService(
            catalog: AVFoundationAudioInputDeviceCatalog(),
            updateSource: AVFoundationAudioInputDeviceUpdateSource()
        ),
        cameraDeviceService: CameraDeviceService = CameraDeviceService(
            catalog: AVFoundationCameraDeviceCatalog()
        ),
        cameraPreviewPanelController: CameraPreviewPanelController = CameraPreviewPanelController(),
        audioLevelMonitorFactory: @escaping () -> any AudioLevelMonitor = {
            AVCaptureAudioLevelMonitor()
        },
        fileWorkflowService: ExportedFileWorkflowService = ExportedFileWorkflowService(
            client: AppKitExportedFileActionClient()
        ),
        bookmarkedDirectoryPicker: any BookmarkedDirectoryPicker = AppKitBookmarkedDirectoryPicker(),
        quickExportService: QuickExportService? = nil,
        screenshotCaptureService: ScreenshotCaptureService? = nil,
        permissionGuidanceService: PermissionGuidanceService = PermissionGuidanceService(),
        lastCaptureRecordingPlanner: LastCaptureRecordingPlanner = LastCaptureRecordingPlanner(),
        screenshotCapturePlanner: ScreenshotCapturePlanner = ScreenshotCapturePlanner(),
        activeWindowCatalog: any ActiveWindowCatalog = CoreGraphicsActiveWindowCatalog(),
        activeWindowCaptureTargetResolver: ActiveWindowCaptureTargetResolver = ActiveWindowCaptureTargetResolver(),
        pointerDisplayProvider: any PointerDisplayProvider = AppKitPointerDisplayProvider(),
        fullscreenCaptureTargetResolver: FullscreenCaptureTargetResolver = FullscreenCaptureTargetResolver(),
        screenshotThumbnailPresenter: any ScreenshotThumbnailPresenter = AppKitScreenshotThumbnailPresenter(),
        appMetadata: AppMetadata = LuxelCompositionRoot.appMetadata,
        recorder: (any CaptureRecorder)? = nil,
        audioRecorder: any AudioRecorder = LuxelCompositionRoot.audioRecorder()
    ) {
        self.settingsStore = settingsStore
        self.permissionClient = permissionClient
        self.launchAtLoginService = launchAtLoginService
        self.recordingHistoryService = recordingHistoryService
        self.captureTargetService = captureTargetService
        self.captureExclusionRegistry = captureExclusionRegistry
        self.recordingFramePanelController = recordingFramePanelController
        self.audioInputDeviceService = audioInputDeviceService
        self.cameraDeviceService = cameraDeviceService
        self.cameraPreviewPanelController = cameraPreviewPanelController
        self.audioLevelMonitorFactory = audioLevelMonitorFactory
        self.fileWorkflowService = fileWorkflowService
        self.bookmarkedDirectoryPicker = bookmarkedDirectoryPicker
        self.quickExportService = quickExportService
            ?? LuxelCompositionRoot.quickExportService(fileWorkflowService: fileWorkflowService)
        self.screenshotCaptureService = screenshotCaptureService
            ?? LuxelCompositionRoot.screenshotCaptureService(history: recordingHistoryService)
        self.permissionGuidanceService = permissionGuidanceService
        self.lastCaptureRecordingPlanner = lastCaptureRecordingPlanner
        self.screenshotCapturePlanner = screenshotCapturePlanner
        self.activeWindowCatalog = activeWindowCatalog
        self.activeWindowCaptureTargetResolver = activeWindowCaptureTargetResolver
        self.pointerDisplayProvider = pointerDisplayProvider
        self.fullscreenCaptureTargetResolver = fullscreenCaptureTargetResolver
        self.screenshotThumbnailPresenter = screenshotThumbnailPresenter
        self.appMetadata = appMetadata
        let recordingOutputFinalizer = LuxelCompositionRoot.recordingOutputFinalizer()
        self.recordingLifecycleService = RecordingLifecycleService(
            recorder: recorder ?? LuxelCompositionRoot.captureRecorder(
                exclusionRegistry: captureExclusionRegistry
            ),
            history: recordingHistoryService,
            userNotifier: UserNotificationsNotifier(),
            outputFinalizer: recordingOutputFinalizer
        )
        self.audioRecordingLifecycleService = AudioRecordingLifecycleService(
            recorder: audioRecorder,
            history: recordingHistoryService,
            outputFinalizer: recordingOutputFinalizer
        )
        self.settings = (try? settingsStore.load()) ?? LuxelCompositionRoot.defaultSettings
        self.launchAtLogin = launchAtLoginService.isEnabled()
    }
}
