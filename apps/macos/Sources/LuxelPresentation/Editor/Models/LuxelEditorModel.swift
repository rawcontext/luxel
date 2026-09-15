import AVKit
import Foundation
import LuxelCore
import Observation

@MainActor
@Observable
public final class LuxelEditorModel {
    enum Status: Equatable {
        case empty
        case loading(String)
        case ready
        case exporting
        case savingOriginal
        case copyingFrame
        case savingFrame
        case copiedFrame
        case savedFrame(URL)
        case exported(URL)
        case exportedBatch([URL])
        case saved(URL)
        case canceled
        case discarded(String)
        case failed(String)
    }

    static let sizePresets = EditorSizePreset.allCases
    static let defaultFrameRate = 60

    var source: SourceMedia?
    var isAutomaticTitlePending = false
    var status: Status = .empty
    var format: ExportFormat = .mp4
    var selectedFormats: [ExportFormat] = [.mp4]
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 1
    var sizePreset: EditorSizePreset? = .original
    var outputWidth = 1280
    var outputHeight = 720
    var frameRate = defaultFrameRate
    var playbackSpeed: PlaybackSpeed = .normal
    var shouldMute = false
    var audioVolume = 1.0
    var normalizeAudio = false
    var studioVoiceEnabled = false
    var shouldCrop = true
    var quality: ExportQuality = .balanced
    var gifLoopModeKind: EditorGIFLoopModeKind = .forever
    var gifLoopCount = 3
    var gifDithering: GIFDitheringMode = .auto
    var outputDirectory = LuxelEditorModel.defaultRecordingsDirectory
    var outputDirectoryBookmark: BookmarkedDirectory?
    var recordingNavigationURLs: [URL] = []
    var recordingNavigationIndex: Int?
    var transcript: TurnSegmentedTranscript? {
        didSet {
            refreshDetectedSpeakerVoices()
            rebuildTranscriptWordCache()
        }
    }
    var isTranscriptExtractionActive = false
    var isTranscriptPanelVisible = false
    var transcriptExtractionStartedAt: Date?
    var transcriptExtractionProgress: Double?
    var transcriptFailureMessage: String?
    var transcriptEditPlan: TimelineEditPlan = .empty {
        didSet {
            refreshVisibleTranscriptWordCache()
        }
    }
    var transcriptDisplayRevision = 0
    var selectedTranscriptWordIDs: Set<TranscriptEditableWord.ID> = []
    var transcriptWordSelectionAnchorID: TranscriptEditableWord.ID?
    var transcriptEditStatusMessage: String?
    var lastTranscriptCutID: String?
    var isEditedPreviewReady = true
    var detectedSpeakerVoices: [DetectedSpeakerVoice] = []
    var knownSpeakerOptions: [KnownSpeakerProfile] = []
    var ignoredSpeakerVoiceIDs: Set<String> = []
    var speakerCountMode: EditorSpeakerCountMode = .automatic
    var exactSpeakerCount = 1
    var minimumSpeakerCount = 1
    var maximumSpeakerCount = 3
    var appliedSpeakerCountHint: TranscriptSpeakerCountHint = .automatic
    var isSpeakerModelPreparing = false
    var speechRecognitionAuthorizationState: SpeechRecognitionAuthorizationState?
    var currentPlaybackTime: TimeInterval = 0
    var keystrokeTimeline: KeystrokeTimeline?
    var keystrokeOptions: KeystrokeRenderOptions?
    let configuredSupportedFormats: [ExportFormat]
    var exportProgress: ExportProgressSnapshot?
    var exportJobs: [ExportJobSnapshot] = []
    var exportEstimatesByFormat: [ExportFormat: ExportEstimate] = [:]
    var estimatingExportSizeFormats: Set<ExportFormat> = []
    var exportEstimate: ExportEstimate? {
        get {
            exportEstimatesByFormat[format]
        }
        set {
            if let newValue {
                exportEstimatesByFormat[format] = newValue
            } else {
                exportEstimatesByFormat.removeValue(forKey: format)
            }
        }
    }
    var isEstimatingExportSize: Bool {
        !estimatingExportSizeFormats.isEmpty
    }
    var editorUndoStack = UndoStack(initialState: EditorDraftState.defaults)

    @ObservationIgnored var player = AVPlayer()
    @ObservationIgnored let metadataReader: any MediaMetadataReader
    @ObservationIgnored let exportService: ExportService
    @ObservationIgnored let exportSizeEstimationService: ExportSizeEstimationService
    @ObservationIgnored let passthroughExportService: PassthroughExportService
    @ObservationIgnored let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored let frameGrabService: FrameGrabService
    @ObservationIgnored let audioMixResolutionService: AudioMixResolutionService
    @ObservationIgnored let audioTranscriptService: (any AudioTranscriptService)?
    @ObservationIgnored let speakerNamingService: SpeakerVoiceNamingService?
    @ObservationIgnored let speakerModelStore: (any SpeakerDiarizationModelStore)?
    @ObservationIgnored var exampleClipPlaybackTask: Task<Void, Never>?
    @ObservationIgnored var speakerModelStatePollingTask: Task<Void, Never>?
    @ObservationIgnored let speechRecognitionAuthorizationService: (any SpeechRecognitionAuthorizationService)?
    @ObservationIgnored let fileSystem: any FileSystem
    @ObservationIgnored let directoryAccessService: BookmarkedDirectoryAccessService?
    var playbackRequested = false
    @ObservationIgnored var playbackTimeObserver: PlaybackTimeObserver?
    @ObservationIgnored var pendingPlayerSeekTarget: TimeInterval?
    @ObservationIgnored var isPlayerSeekInProgress = false
    @ObservationIgnored var exportTask: Task<Void, Never>?
    @ObservationIgnored var frameGrabTask: Task<Void, Never>?
    @ObservationIgnored var previewAudioMixTask: Task<Void, Never>?
    @ObservationIgnored var transcriptTask: Task<Void, Never>?
    @ObservationIgnored var previewCompositionTask: Task<Void, Never>?
    @ObservationIgnored var speechRecognitionAuthorizationTask: Task<Void, Never>?
    @ObservationIgnored var transcriptSourceContext: TranscriptSourceContext = .unknown
    @ObservationIgnored var cachedTranscriptWords: [TranscriptEditableWord] = []
    @ObservationIgnored var cachedVisibleTranscriptWords: [TranscriptEditableWord] = []
    @ObservationIgnored var cachedVisibleTranscriptWordIDs: Set<TranscriptEditableWord.ID> = []
    @ObservationIgnored var cachedVisibleTranscriptWordIndexByID: [TranscriptEditableWord.ID: Int] =
        [:]
    @ObservationIgnored var cachedVisibleTranscriptTurnIDs: Set<TranscriptTurn.ID> = []
    @ObservationIgnored var cachedTranscriptCutReviewItems: [TranscriptCutReviewItem] = []
    @ObservationIgnored var exportMemoryByFormat: [ExportFormat: ExportMemory]
    @ObservationIgnored var lastSelectedExportFormat: ExportFormat?
    @ObservationIgnored var onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)?
    @ObservationIgnored var onLastSelectedExportFormatChange: (@MainActor (ExportFormat) -> Void)?
    @ObservationIgnored var onConfirmDiscardChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var onDiscardRecording: (@MainActor (URL) -> Void)?
    @ObservationIgnored var onSourceFileRenamed: (@MainActor (URL, URL) throws -> Void)?
    @ObservationIgnored var onExportCompleted: (@MainActor ([URL]) -> Void)?
    @ObservationIgnored var onTranscriptExtractionStarted: (@MainActor (URL) -> Void)?
    @ObservationIgnored let errorReporter: any ErrorReporter

    public init(
        metadataReader: any MediaMetadataReader = AVFoundationMediaMetadataReader(),
        exportService: ExportService = ExportService(
            exporter: NativeMediaExporter(),
            fileSystem: LocalFileSystem()
        ),
        exportSizeEstimationService: ExportSizeEstimationService = ExportSizeEstimationService(
            estimator: NativeExportSizeEstimator()
        ),
        passthroughExportService: PassthroughExportService = PassthroughExportService(
            fileSystem: LocalFileSystem(),
            trimmedExporter: AVFoundationPassthroughExporter()
        ),
        fileWorkflowService: ExportedFileWorkflowService = ExportedFileWorkflowService(
            client: AppKitExportedFileActionClient()
        ),
        frameGrabService: FrameGrabService = FrameGrabService(
            frameGrabber: AVFoundationFrameGrabber(),
            fileWriter: LocalFrameGrabFileWriter(),
            destinationClient: AppKitFrameGrabDestinationClient()
        ),
        audioPeakAnalyzer: any AudioPeakAnalyzer = AVAssetReaderAudioPeakAnalyzer(),
        audioTranscriptService: (any AudioTranscriptService)? = nil,
        speakerNamingService: SpeakerVoiceNamingService? = nil,
        speakerModelStore: (any SpeakerDiarizationModelStore)? = nil,
        speechRecognitionAuthorizationService:
            (any SpeechRecognitionAuthorizationService)? = nil,
        fileSystem: any FileSystem = LocalFileSystem(),
        codecAvailability: CodecAvailability = .none,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil,
        exportMemory: [ExportFormat: ExportMemory] = [:],
        lastSelectedExportFormat: ExportFormat? = nil,
        onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil,
        onLastSelectedExportFormatChange: (@MainActor (ExportFormat) -> Void)? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) {
        self.metadataReader = metadataReader
        self.exportService = exportService
        self.exportSizeEstimationService = exportSizeEstimationService
        self.passthroughExportService = passthroughExportService
        self.fileWorkflowService = fileWorkflowService
        self.frameGrabService = frameGrabService
        self.audioMixResolutionService = AudioMixResolutionService(analyzer: audioPeakAnalyzer)
        self.audioTranscriptService = audioTranscriptService
        self.speakerNamingService = speakerNamingService
        self.speakerModelStore = speakerModelStore
        self.speechRecognitionAuthorizationService = speechRecognitionAuthorizationService
        self.fileSystem = fileSystem
        self.directoryAccessService = directoryAccessService
        self.configuredSupportedFormats = codecAvailability.availableExportFormats
        self.exportMemoryByFormat = exportMemory
        self.lastSelectedExportFormat = lastSelectedExportFormat
        self.onExportMemoryChange = onExportMemoryChange
        self.onLastSelectedExportFormatChange = onLastSelectedExportFormatChange
        self.errorReporter = errorReporter
        let initialFormat = Self.preferredVideoExportFormat(
            from: self.configuredSupportedFormats,
            lastSelectedExportFormat: lastSelectedExportFormat
        )
        format = initialFormat
        selectedFormats = [initialFormat]
        player.actionAtItemEnd = .none
        installPlaybackLoopObserver()
    }

    public var confirmDiscard = true
}
