import Foundation
import LuxelCore
import LuxelPresentation
import Observation

struct ReplayBufferConsentPrompt: Equatable {
    let configuration: ReplayBufferConfiguration
}

@MainActor
@Observable
final class LuxelMenuModel {
    var settings: AppSettings
    var launchAtLogin: Bool
    var screenRecordingStatus: PermissionStatus = .unknown
    var microphoneStatus: PermissionStatus = .unknown
    var cameraStatus: PermissionStatus = .unknown
    var inputMonitoringStatus: PermissionStatus = .unknown
    var keystrokeCaptureStatus: KeystrokeCaptureStatus = .idle
    var audioLevelSample: AudioLevelSample = .silent
    var audioInputDevices: [AudioInputDeviceOption] = [.systemDefault]
    var cameraDevices: [CameraDeviceOption] = []
    var notchDisplays: [NotchDisplayDescriptor] = []
    var recentRecordings: [PastRecording] = []
    var recentRecordingFilter: RecordingHistoryFilter = .all
    var captureTargets: [CaptureTargetOption] = []
    var selectedCaptureTargetID: String?
    var captureTargetStatusMessage: String?
    var recordingState: RecordingMenuState = .idle {
        didSet {
            if !recordingState.keepsActiveNotchRecordingAction {
                activeNotchRecordingActionID = nil
            }
        }
    }
    var recordingNoticeMessage: String?
    var recordingActionErrorMessage: String?
    var replayBufferState: ReplayBufferState = .disarmed
    var quickExportProgress: QuickExportProgressPresentation?
    var recoveryState: RecordingRecoveryMenuState?
    var permissionPrompt: PermissionPrompt?
    var replayBufferConsentPrompt: ReplayBufferConsentPrompt?
    var recoveryPrompt: RecoveryPrompt?
    var automationPrompt: AutomationURLPrompt?
    var knownSpeakers: [KnownSpeakerProfile] = []
    var expandedKnownSpeakerID: UUID?
    let appMetadata: AppMetadata

    @ObservationIgnored let speakerDiarizationModelStore: any SpeakerDiarizationModelStore =
        LuxelCompositionRoot.speakerDiarizationModelStore
    @ObservationIgnored let knownSpeakerProfileStore: any KnownSpeakerProfileStore =
        LuxelCompositionRoot.knownSpeakerProfileStore()
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
    @ObservationIgnored let recordingAudioLevelMonitorFactory: () -> any AudioLevelMonitor
    @ObservationIgnored let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored let bookmarkedDirectoryPicker: any BookmarkedDirectoryPicker
    @ObservationIgnored let directoryAccessService: BookmarkedDirectoryAccessService
    @ObservationIgnored let quickExportService: QuickExportService
    @ObservationIgnored let replayBufferService: ReplayBufferService?
    @ObservationIgnored let replayBufferClipService: ReplayBufferClipService?
    @ObservationIgnored var recordingStartTask: Task<ActiveRecording, any Error>?
    @ObservationIgnored var quickExportTask: Task<QuickExportResult, any Error>?
    @ObservationIgnored let permissionGuidanceService: PermissionGuidanceService
    @ObservationIgnored let lastCaptureRecordingPlanner: LastCaptureRecordingPlanner
    @ObservationIgnored let activeWindowCatalog: any ActiveWindowCatalog
    @ObservationIgnored let activeWindowCaptureTargetResolver: ActiveWindowCaptureTargetResolver
    @ObservationIgnored let pointerDisplayProvider: any PointerDisplayProvider
    @ObservationIgnored let notchDisplayProvider: any NotchDisplayProvider
    @ObservationIgnored let notchCoordinator: NotchCoordinator
    @ObservationIgnored let fullscreenCaptureTargetResolver: FullscreenCaptureTargetResolver
    @ObservationIgnored let errorReporter: any ErrorReporter
    @ObservationIgnored var notchPresentationState: NotchPresentationState = .collapsed
    @ObservationIgnored var activeNotchRecordingActionID: NotchActivityActionID?
    @ObservationIgnored weak var configuredEditorModel: LuxelEditorModel?
    @ObservationIgnored var commandLineNonces: [String: Date] = [:]
    @ObservationIgnored var commandLineJobs: [
        UUID: Task<CommandLineAutomationResult, any Error>
        ] = [:]
    @ObservationIgnored lazy var keystrokeLivePreviewPanelController =
        KeystrokeLivePreviewPanelController(exclusionRegistry: captureExclusionRegistry)
    @ObservationIgnored lazy var keystrokeRecordingSession: any KeystrokeRecordingSessionControlling =
        KeystrokeRecordingSession(
            onStatus: { [weak self] (status: KeystrokeCaptureStatus) in
                self?.keystrokeCaptureStatus = status
                switch status {
                case .paused(.secureInput):
                    self?.recordingNoticeMessage = "Keystrokes paused while secure input is active."
                case .permissionDenied:
                    self?.recordingNoticeMessage =
                        "Keystroke capture is unavailable. Allow Input Monitoring, then relaunch Luxel."
                case .eventDeliveryUnavailable:
                    self?.recordingNoticeMessage =
                        "macOS stopped delivering keystrokes. The screen recording is still running."
                case .eventDeliveryRecovered:
                    self?.recordingNoticeMessage =
                        "Keystroke capture was briefly interrupted and recovered."
                case .idle, .active, .paused(.user), .paused(.recording):
                    break
                }
            },
            onChips: { [weak self] chips in
                guard let self else { return }
                Task {
                    await self.keystrokeLivePreviewPanelController.present(
                        chips: chips,
                        options: self.settings.keystrokeRenderOptions,
                        isEnabled: self.settings.keystrokeLivePreviewEnabled
                    )
                }
            }
        )

    init(
        settingsStore: any SettingsStore = LuxelCompositionRoot.settingsStore(),
        permissionClient: any PermissionClient = ApplePermissionClient(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(
            client: SMAppServiceLaunchAtLoginClient()
        ),
        recordingHistoryService: RecordingHistoryService =
            LuxelCompositionRoot.recordingHistoryService(),
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
        directoryAccessService: BookmarkedDirectoryAccessService =
            LuxelCompositionRoot
            .bookmarkedDirectoryAccessService(),
        quickExportService: QuickExportService? = nil,
        replayBufferService: ReplayBufferService? = nil,
        replayBufferClipService: ReplayBufferClipService? = nil,
        permissionGuidanceService: PermissionGuidanceService = PermissionGuidanceService(),
        lastCaptureRecordingPlanner: LastCaptureRecordingPlanner = LastCaptureRecordingPlanner(),
        activeWindowCatalog: any ActiveWindowCatalog = CoreGraphicsActiveWindowCatalog(),
        activeWindowCaptureTargetResolver: ActiveWindowCaptureTargetResolver =
            ActiveWindowCaptureTargetResolver(),
        pointerDisplayProvider: any PointerDisplayProvider = AppKitPointerDisplayProvider(),
        notchDisplayProvider: any NotchDisplayProvider = AppKitNotchDisplayProvider(),
        notchPresenter: (any NotchPresenter)? = nil,
        fullscreenCaptureTargetResolver: FullscreenCaptureTargetResolver =
            FullscreenCaptureTargetResolver(),
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        appMetadata: AppMetadata = LuxelCompositionRoot.appMetadata,
        recorder: (any CaptureRecorder)? = nil,
        audioRecorder: (any AudioRecorder)? = nil
    ) {
        let recordingAudioLevelBroadcaster = AudioLevelBroadcaster()

        self.settingsStore = settingsStore; self.permissionClient = permissionClient
        self.launchAtLoginService = launchAtLoginService; self.recordingHistoryService = recordingHistoryService
        self.captureTargetService = captureTargetService; self.captureExclusionRegistry = captureExclusionRegistry
        self.recordingFramePanelController = recordingFramePanelController
        self.audioInputDeviceService = audioInputDeviceService; self.cameraDeviceService = cameraDeviceService
        self.cameraPreviewPanelController = cameraPreviewPanelController
        self.audioLevelMonitorFactory = audioLevelMonitorFactory
        self.recordingAudioLevelMonitorFactory = { recordingAudioLevelBroadcaster }
        self.fileWorkflowService = fileWorkflowService; self.bookmarkedDirectoryPicker = bookmarkedDirectoryPicker
        self.directoryAccessService = directoryAccessService
        self.quickExportService =
            quickExportService
            ?? LuxelCompositionRoot.quickExportService(fileWorkflowService: fileWorkflowService)
        let resolvedReplayBufferService =
            replayBufferService
            ?? LuxelCompositionRoot.replayBufferService(
                settingsStore: settingsStore,
                exclusionRegistry: captureExclusionRegistry
            )
        self.replayBufferService = resolvedReplayBufferService
        self.replayBufferClipService =
            replayBufferClipService
            ?? LuxelCompositionRoot.replayBufferClipService(
                replayBufferService: resolvedReplayBufferService,
                history: recordingHistoryService
            )
        self.permissionGuidanceService = permissionGuidanceService
        self.lastCaptureRecordingPlanner = lastCaptureRecordingPlanner; self.activeWindowCatalog = activeWindowCatalog
        self.activeWindowCaptureTargetResolver = activeWindowCaptureTargetResolver
        self.pointerDisplayProvider = pointerDisplayProvider; self.notchDisplayProvider = notchDisplayProvider
        let resolvedNotchPresenter = notchPresenter
            ?? OverlayPanelNotchPresenter(exclusionRegistry: captureExclusionRegistry)
        self.notchCoordinator = NotchCoordinator(presenter: resolvedNotchPresenter)
        self.fullscreenCaptureTargetResolver = fullscreenCaptureTargetResolver
        self.errorReporter = errorReporter
        self.appMetadata = appMetadata
        let lifecycleServices = Self.makeRecordingLifecycleServices(.init(
            broadcaster: recordingAudioLevelBroadcaster, exclusionRegistry: captureExclusionRegistry,
            history: recordingHistoryService, replayBufferService: resolvedReplayBufferService,
            recorder: recorder, audioRecorder: audioRecorder
        ))
        recordingLifecycleService = lifecycleServices.video; audioRecordingLifecycleService = lifecycleServices.audio
        let loadedSettings = (try? settingsStore.load()) ?? LuxelCompositionRoot.defaultSettings
        self.settings = loadedSettings; self.launchAtLogin = loadedSettings.launchAtLogin
        finishInitialization()
    }

    private func finishInitialization() {
        reconcileLaunchAtLoginWithSettings()
        prepareSpeakerModelIfNeeded()
    }

    private static func makeRecordingLifecycleServices(
        _ dependencies: RecordingLifecycleDependencies
    ) -> RecordingLifecycleServices {
        let outputFinalizer = LuxelCompositionRoot.recordingOutputFinalizer()
        let publishAudioLevel: @Sendable (AudioLevelSample) -> Void = {
            dependencies.broadcaster.publish($0)
        }
        let video = RecordingLifecycleService(
            recorder: dependencies.recorder
                ?? LuxelCompositionRoot.captureRecorder(
                    exclusionRegistry: dependencies.exclusionRegistry,
                    audioLevelHandler: publishAudioLevel
                ),
            history: dependencies.history,
            userNotifier: UserNotificationsNotifier(),
            outputFinalizer: outputFinalizer,
            replayBufferService: dependencies.replayBufferService
        )
        let audio = AudioRecordingLifecycleService(
            recorder: dependencies.audioRecorder
                ?? LuxelCompositionRoot.audioRecorder(audioLevelHandler: publishAudioLevel),
            history: dependencies.history,
            outputFinalizer: outputFinalizer
        )
        return RecordingLifecycleServices(video: video, audio: audio)
    }
}

private struct RecordingLifecycleDependencies {
    let broadcaster: AudioLevelBroadcaster
    let exclusionRegistry: CaptureExclusionRegistry
    let history: RecordingHistoryService
    let replayBufferService: ReplayBufferService?
    let recorder: (any CaptureRecorder)?
    let audioRecorder: (any AudioRecorder)?
}

private struct RecordingLifecycleServices {
    let video: RecordingLifecycleService
    let audio: AudioRecordingLifecycleService
}
