import LuxelCore
import Observation

@MainActor
@Observable
final class LuxelMenuModel {
    var settings: AppSettings
    var launchAtLogin: Bool
    var screenRecordingStatus: PermissionStatus = .unknown
    var microphoneStatus: PermissionStatus = .unknown
    var audioLevelSample: AudioLevelSample = .silent
    var audioInputDevices: [AudioInputDeviceOption] = [.systemDefault]
    var recentRecordings: [PastRecording] = []
    var captureTargets: [CaptureTargetOption] = []
    var selectedCaptureTargetID: String?
    var captureTargetStatusMessage: String?
    var recordingState: RecordingMenuState = .idle
    var recordingNoticeMessage: String?
    var recordingActionErrorMessage: String?
    var quickExportStatusMessage: String?
    var recoveryState: RecordingRecoveryMenuState?
    var permissionPrompt: PermissionPrompt?
    var recoveryPrompt: RecoveryPrompt?
    let appMetadata: AppMetadata

    @ObservationIgnored let settingsStore: any SettingsStore
    @ObservationIgnored let permissionClient: any PermissionClient
    @ObservationIgnored let launchAtLoginService: LaunchAtLoginService
    @ObservationIgnored let recordingHistoryService: RecordingHistoryService
    @ObservationIgnored let recordingLifecycleService: RecordingLifecycleService
    @ObservationIgnored let audioRecordingLifecycleService: AudioRecordingLifecycleService
    @ObservationIgnored let captureTargetService: CaptureTargetService
    @ObservationIgnored let audioInputDeviceService: AudioInputDeviceService
    @ObservationIgnored let audioLevelMonitorFactory: () -> any AudioLevelMonitor
    @ObservationIgnored let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored let quickExportService: QuickExportService
    @ObservationIgnored let permissionGuidanceService: PermissionGuidanceService
    @ObservationIgnored let lastCaptureRecordingPlanner: LastCaptureRecordingPlanner

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
        audioInputDeviceService: AudioInputDeviceService = AudioInputDeviceService(
            catalog: AVFoundationAudioInputDeviceCatalog(),
            updateSource: AVFoundationAudioInputDeviceUpdateSource()
        ),
        audioLevelMonitorFactory: @escaping () -> any AudioLevelMonitor = {
            AVCaptureAudioLevelMonitor()
        },
        fileWorkflowService: ExportedFileWorkflowService = ExportedFileWorkflowService(
            client: AppKitExportedFileActionClient()
        ),
        quickExportService: QuickExportService? = nil,
        permissionGuidanceService: PermissionGuidanceService = PermissionGuidanceService(),
        lastCaptureRecordingPlanner: LastCaptureRecordingPlanner = LastCaptureRecordingPlanner(),
        appMetadata: AppMetadata = LuxelCompositionRoot.appMetadata,
        recorder: any CaptureRecorder = LuxelCompositionRoot.captureRecorder(),
        audioRecorder: any AudioRecorder = LuxelCompositionRoot.audioRecorder()
    ) {
        self.settingsStore = settingsStore
        self.permissionClient = permissionClient
        self.launchAtLoginService = launchAtLoginService
        self.recordingHistoryService = recordingHistoryService
        self.captureTargetService = captureTargetService
        self.audioInputDeviceService = audioInputDeviceService
        self.audioLevelMonitorFactory = audioLevelMonitorFactory
        self.fileWorkflowService = fileWorkflowService
        self.quickExportService = quickExportService
            ?? LuxelCompositionRoot.quickExportService(fileWorkflowService: fileWorkflowService)
        self.permissionGuidanceService = permissionGuidanceService
        self.lastCaptureRecordingPlanner = lastCaptureRecordingPlanner
        self.appMetadata = appMetadata
        self.recordingLifecycleService = RecordingLifecycleService(
            recorder: recorder,
            history: recordingHistoryService,
            userNotifier: UserNotificationsNotifier()
        )
        self.audioRecordingLifecycleService = AudioRecordingLifecycleService(
            recorder: audioRecorder,
            history: recordingHistoryService
        )
        self.settings = (try? settingsStore.load()) ?? LuxelCompositionRoot.defaultSettings
        self.launchAtLogin = launchAtLoginService.isEnabled()
    }
}
