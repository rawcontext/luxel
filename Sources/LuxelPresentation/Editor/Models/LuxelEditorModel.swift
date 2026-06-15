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
    static let playbackSpeedDetents: [Double] = [0.25, 0.5, 1, 1.5, 2, 3, 4]

    var source: SourceMedia?
    var status: Status = .empty
    var format: ExportFormat = .mp4
    var selectedFormats: [ExportFormat] = [.mp4]
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 1
    var sizePreset: EditorSizePreset? = .original
    var outputWidth = 1280
    var outputHeight = 720
    var frameRate = 30
    var playbackSpeed: PlaybackSpeed = .normal
    var shouldMute = false
    var audioVolume = 1.0
    var normalizeAudio = false
    var shouldCrop = true
    var quality: ExportQuality = .balanced
    var gifLoopModeKind: EditorGIFLoopModeKind = .forever
    var gifLoopCount = 3
    var gifDithering: GIFDitheringMode = .auto
    var outputDirectory = LuxelEditorModel.defaultRecordingsDirectory
    let supportedFormats: [ExportFormat]
    var exportProgress: ExportProgressSnapshot?
    var exportJobs: [ExportJobSnapshot] = []
    var exportEstimate: ExportEstimate?
    var isEstimatingExportSize = false
    var editorUndoStack = UndoStack(initialState: EditorDraftState.defaults)

    @ObservationIgnored var player = AVPlayer()
    @ObservationIgnored let metadataReader: any MediaMetadataReader
    @ObservationIgnored let exportService: ExportService
    @ObservationIgnored let exportSizeEstimationService: ExportSizeEstimationService
    @ObservationIgnored let passthroughExportService: PassthroughExportService
    @ObservationIgnored let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored let frameGrabService: FrameGrabService
    @ObservationIgnored let audioMixResolutionService: AudioMixResolutionService
    @ObservationIgnored let fileSystem: any FileSystem
    @ObservationIgnored var playbackRequested = false
    @ObservationIgnored var playbackTimeObserver: PlaybackTimeObserver?
    @ObservationIgnored var exportTask: Task<Void, Never>?
    @ObservationIgnored var frameGrabTask: Task<Void, Never>?
    @ObservationIgnored var previewAudioMixTask: Task<Void, Never>?
    @ObservationIgnored var exportMemoryByFormat: [ExportFormat: ExportMemory]
    @ObservationIgnored var onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)?
    @ObservationIgnored var onConfirmDiscardChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored var onDiscardRecording: (@MainActor (URL) -> Void)?

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
            fileWriter: LocalScreenshotFileWriter(),
            destinationClient: AppKitScreenshotDestinationClient()
        ),
        audioPeakAnalyzer: any AudioPeakAnalyzer = AVAssetReaderAudioPeakAnalyzer(),
        fileSystem: any FileSystem = LocalFileSystem(),
        codecAvailability: CodecAvailability = .none,
        exportMemory: [ExportFormat: ExportMemory] = [:],
        onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil
    ) {
        self.metadataReader = metadataReader
        self.exportService = exportService
        self.exportSizeEstimationService = exportSizeEstimationService
        self.passthroughExportService = passthroughExportService
        self.fileWorkflowService = fileWorkflowService
        self.frameGrabService = frameGrabService
        self.audioMixResolutionService = AudioMixResolutionService(analyzer: audioPeakAnalyzer)
        self.fileSystem = fileSystem
        self.supportedFormats = codecAvailability.availableExportFormats
        self.exportMemoryByFormat = exportMemory
        self.onExportMemoryChange = onExportMemoryChange
        player.actionAtItemEnd = .none
        installPlaybackLoopObserver()
    }

    public var confirmDiscard = true
}

extension LuxelEditorModel {
    var hasSource: Bool {
        source != nil
    }

    var duration: TimeInterval {
        source?.duration ?? 1
    }

    var minimumTrimDuration: TimeInterval {
        min(0.1, max(0.001, duration / 100))
    }

    var canIncludeAudio: Bool {
        source?.hasAudio == true && !format.dropsAudio
    }

    var maximumFrameRate: Int {
        max(1, source?.nominalFrameRate.framesPerSecond ?? 120)
    }

    var availableQualities: [ExportQuality] {
        ExportQuality.availableQualities(for: format)
    }

    var canChooseQuality: Bool {
        availableQualities.count > 1
    }

    var showsGIFOptions: Bool {
        format == .gif
    }

    var gifLoopMode: GIFLoopMode {
        switch gifLoopModeKind {
        case .forever:
            .forever
        case .none:
            .none
        case .count:
            .count(gifLoopCount)
        case .bounce:
            .bounce
        }
    }

    var selectedFormatSummary: String {
        if selectedFormats.count == 1 {
            return selectedFormats[0].prettyName
        }

        return "\(selectedFormats.count) Formats"
    }

    var includesAudio: Bool {
        canIncludeAudio && !shouldMute
    }

    var canAdjustAudioMix: Bool {
        includesAudio
    }

    var audioVolumePercentSummary: String {
        "\(Int((audioVolume * 100).rounded()))%"
    }

    var playbackSpeedValue: Double {
        playbackSpeed.value
    }

    var outputDurationSummary: String {
        formatTime(max(minimumTrimDuration, trimEnd - trimStart) / playbackSpeed.value)
    }

    var isExporting: Bool {
        status == .exporting || status == .savingOriginal
    }

    var isGrabbingFrame: Bool {
        frameGrabTask != nil || status == .copyingFrame || status == .savingFrame
    }

    var canExport: Bool {
        hasSource && !isExporting
    }

    var canSaveOriginal: Bool {
        hasSource && !isExporting
    }

    var canDiscard: Bool {
        hasSource && !isExporting
    }

    var canGrabFrame: Bool {
        hasSource && !isExporting && !isGrabbingFrame && player.rate == 0
    }

    var canCancelExport: Bool {
        isExporting && exportTask != nil
    }

    var canRetryExport: Bool {
        hasSource && !isExporting
    }

    var canUndoEditorChange: Bool {
        editorUndoStack.canUndo
    }

    var canRedoEditorChange: Bool {
        editorUndoStack.canRedo
    }

    var showsExportProgressPanel: Bool {
        isExporting || exportProgress != nil || exportedURL != nil || status == .canceled || isRecoverableExportFailure
    }

    var exportPanelTitle: String {
        switch status {
        case .exporting, .savingOriginal:
            exportProgressTitle
        case .exported, .exportedBatch, .saved:
            "Export Complete"
        case .copyingFrame, .savingFrame, .copiedFrame, .savedFrame:
            statusMessage
        case .canceled:
            "Export Canceled"
        case .failed:
            "Export Failed"
        case .discarded:
            "Recording Discarded"
        case .empty, .loading, .ready:
            exportProgressTitle
        }
    }

    var exportPanelMessage: String {
        switch status {
        case .exported(let url), .saved(let url):
            url.lastPathComponent
        case .exportedBatch(let urls):
            "\(urls.count) files exported"
        case .savingOriginal:
            "Copying the source recording without re-encoding."
        case .copyingFrame, .savingFrame, .copiedFrame, .savedFrame:
            statusMessage
        case .failed(let message):
            message
        case .canceled:
            "The export was canceled before the output file was finished."
        default:
            statusMessage
        }
    }

    var exportPanelSystemImage: String {
        switch status {
        case .exporting, .savingOriginal:
            "arrow.triangle.2.circlepath"
        case .exported, .exportedBatch, .saved:
            "checkmark.circle"
        case .copyingFrame:
            "doc.on.clipboard"
        case .savingFrame:
            "photo.badge.arrow.down"
        case .copiedFrame, .savedFrame:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
        case .discarded:
            "trash"
        case .failed:
            "exclamationmark.triangle"
        case .empty, .loading, .ready:
            "square.and.arrow.down"
        }
    }

    var exportProgressTitle: String {
        exportProgress?.actionTitle ?? statusMessage
    }

    var exportProgressValue: Double {
        exportProgress?.progress ?? 0
    }

    var exportEstimateTaskID: ExportEstimateTaskID? {
        guard let source else {
            return nil
        }

        return ExportEstimateTaskID(
            sourceFileURL: source.fileURL,
            format: format,
            trimStart: trimStart,
            trimEnd: trimEnd,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            frameRate: frameRate,
            playbackSpeed: playbackSpeed.value,
            quality: quality,
            gifLoopModeKind: format == .gif ? gifLoopModeKind : nil,
            gifLoopCount: format == .gif ? gifLoopCount : nil,
            gifDithering: format == .gif ? gifDithering : nil,
            shouldMute: shouldMute,
            shouldCrop: shouldCrop
        )
    }

    var exportEstimateSummary: String? {
        if isEstimatingExportSize {
            return "Estimating..."
        }

        guard let exportEstimate else {
            return nil
        }

        let formatted = ByteCountFormatter.string(fromByteCount: exportEstimate.bytes, countStyle: .file)

        switch exportEstimate.confidence {
        case .exact:
            return formatted
        case .modeled, .sampled:
            return "~ \(formatted)"
        }
    }

    var exportedURL: URL? {
        if case .exported(let url) = status {
            return url
        }

        if case .exportedBatch(let urls) = status {
            return urls.first
        }

        if case .saved(let url) = status {
            return url
        }

        return nil
    }

    var usesAlphaPreviewBackground: Bool {
        source?.hasAlpha == true
    }

    var sourceSummary: String {
        guard let source else {
            return "No recording loaded"
        }

        var parts = [
            source.fileURL.lastPathComponent,
            formatTime(source.duration),
            "\(source.pixelSize.width)x\(source.pixelSize.height)",
            source.hasAudio ? "audio" : "no audio"
        ]
        if source.hasAlpha {
            parts.append("alpha")
        }

        return parts.joined(separator: " | ")
    }

    var outputDirectorySummary: String {
        let name = outputDirectory.lastPathComponent
        return name.isEmpty ? outputDirectory.path : name
    }

    var statusMessage: String {
        switch status {
        case .empty:
            "No recording loaded"
        case .loading(let fileName):
            "Loading \(fileName)"
        case .ready:
            sourceSummary
        case .exporting:
            "Exporting \(selectedFormatSummary)"
        case .savingOriginal:
            "Saving original"
        case .copyingFrame:
            "Copying frame"
        case .savingFrame:
            "Saving frame"
        case .copiedFrame:
            "Copied frame"
        case .savedFrame(let url):
            "Saved \(url.lastPathComponent)"
        case .exported(let url):
            "Exported \(url.lastPathComponent)"
        case .exportedBatch(let urls):
            "Exported \(urls.count) files"
        case .saved(let url):
            "Saved \(url.lastPathComponent)"
        case .canceled:
            "Export canceled"
        case .discarded(let fileName):
            "Discarded \(fileName)"
        case .failed(let message):
            message
        }
    }

    public func open(fileURL: URL, outputDirectory: URL) async {
        self.outputDirectory = outputDirectory
        status = .loading(fileURL.lastPathComponent)
        exportProgress = nil
        exportJobs = []
        exportEstimate = nil
        isEstimatingExportSize = false
        player.pause()
        playbackRequested = false
        frameGrabTask?.cancel()
        frameGrabTask = nil
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil

        do {
            let media = try await metadataReader.readSourceMedia(at: fileURL)
            source = media
            trimStart = 0
            trimEnd = media.duration
            playbackSpeed = .normal
            applySizePreset(.original)
            applyFrameRate(media.nominalFrameRate.framesPerSecond)
            applyExportMemory(for: format)
            shouldMute = !media.hasAudio || format.dropsAudio
            let item = AVPlayerItem(url: fileURL)
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            schedulePreviewAudioMixUpdate()
            status = .ready
            resetEditorUndoStack()
        } catch {
            source = nil
            previewAudioMixTask?.cancel()
            previewAudioMixTask = nil
            player.replaceCurrentItem(with: nil)
            status = .failed(errorMessage(error))
            resetEditorUndoStack()
        }
    }

    public func configureExportMemory(
        _ memory: [ExportFormat: ExportMemory],
        onChange: (@MainActor (ExportFormat, ExportMemory) -> Void)? = nil
    ) {
        exportMemoryByFormat = memory
        onExportMemoryChange = onChange
        applyExportMemory(for: format)
        resetEditorUndoStack()
    }

    public func configureDiscard(
        confirmDiscard: Bool,
        onDiscard: (@MainActor (URL) -> Void)? = nil,
        onConfirmDiscardChange: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.confirmDiscard = confirmDiscard
        self.onDiscardRecording = onDiscard
        self.onConfirmDiscardChange = onConfirmDiscardChange
    }

    func setConfirmDiscard(_ confirmDiscard: Bool) {
        guard self.confirmDiscard != confirmDiscard else {
            return
        }

        self.confirmDiscard = confirmDiscard
        onConfirmDiscardChange?(confirmDiscard)
    }

    public func reportImportFailure(_ error: Error) {
        source = nil
        exportProgress = nil
        exportEstimate = nil
        isEstimatingExportSize = false
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        player.replaceCurrentItem(with: nil)
        status = .failed(errorMessage(error))
        resetEditorUndoStack()
    }

    func setFormat(_ nextFormat: ExportFormat) {
        guard supportedFormats.contains(nextFormat) else {
            return
        }

        format = nextFormat
        selectedFormats = [nextFormat]
        applyExportMemory(for: nextFormat)

        if !canIncludeAudio {
            shouldMute = true
        }

        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setFormatSelection(_ nextFormat: ExportFormat, isSelected: Bool) {
        guard supportedFormats.contains(nextFormat) else {
            return
        }

        if isSelected {
            if !selectedFormats.contains(nextFormat) {
                selectedFormats.append(nextFormat)
                selectedFormats = supportedFormats.filter(selectedFormats.contains)
            }
            format = nextFormat
            applyExportMemory(for: nextFormat)
        } else {
            guard selectedFormats.count > 1 else {
                return
            }

            selectedFormats.removeAll { $0 == nextFormat }
            if format == nextFormat, let replacement = selectedFormats.first {
                format = replacement
                applyExportMemory(for: replacement)
            }
        }

        if !canIncludeAudio {
            shouldMute = true
        }

        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setQuality(_ nextQuality: ExportQuality) {
        guard nextQuality.isAvailable(for: format) else {
            quality = ExportQuality.defaultQuality(for: format)
            exportProgress = nil
            recordEditorDraftChange()
            return
        }

        quality = nextQuality
        exportProgress = nil
        recordEditorDraftChange()
    }

    func setGIFLoopModeKind(_ kind: EditorGIFLoopModeKind) {
        guard gifLoopModeKind != kind else {
            return
        }

        gifLoopModeKind = kind
        recordEditorDraftChange()
    }

    func setGIFLoopCount(_ count: Int) {
        let clampedCount = min(max(count, 1), 100)
        guard gifLoopCount != clampedCount else {
            return
        }

        gifLoopCount = clampedCount
        recordEditorDraftChange(coalescingToken: "gif-loop-count")
    }

    func setGIFDithering(_ dithering: GIFDitheringMode) {
        guard gifDithering != dithering else {
            return
        }

        gifDithering = dithering
        recordEditorDraftChange()
    }

    func setIncludesAudio(_ includesAudio: Bool) {
        shouldMute = !includesAudio
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setAudioVolume(_ volume: Double) {
        let clampedVolume = min(max(volume, 0), 2)
        guard audioVolume != clampedVolume else {
            return
        }

        audioVolume = clampedVolume
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "audio-volume")
    }

    func setNormalizeAudio(_ normalize: Bool) {
        guard normalizeAudio != normalize else {
            return
        }

        normalizeAudio = normalize
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange()
    }

    func setSizePreset(_ preset: EditorSizePreset?) {
        applySizePreset(preset)
        recordEditorDraftChange()
    }

    func setOutputWidth(_ value: Int) {
        outputWidth = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
        recordEditorDraftChange(coalescingToken: "output-width")
    }

    func setOutputHeight(_ value: Int) {
        outputHeight = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
        recordEditorDraftChange(coalescingToken: "output-height")
    }

    func setFrameRate(_ value: Int) {
        applyFrameRate(value)
        recordEditorDraftChange(coalescingToken: "frame-rate")
    }

    func setPlaybackSpeed(_ value: Double) {
        let clampedValue = min(max(value, 0.1), 10)
        guard let nextSpeed = try? PlaybackSpeed(clampedValue), nextSpeed != playbackSpeed else {
            return
        }

        playbackSpeed = nextSpeed
        applyPlaybackRateIfNeeded()
        recordEditorDraftChange(coalescingToken: "playback-speed")
    }

    func setTrimStart(_ value: TimeInterval) {
        let maxStart = max(0, min(duration - minimumTrimDuration, trimEnd - minimumTrimDuration))
        trimStart = min(max(value, 0), maxStart)
        seekPlaybackIntoTrimRangeIfNeeded()
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "trim-start")
    }

    func setTrimEnd(_ value: TimeInterval) {
        let minEnd = min(duration, trimStart + minimumTrimDuration)
        trimEnd = min(max(value, minEnd), duration)
        seekPlaybackIntoTrimRangeIfNeeded()
        schedulePreviewAudioMixUpdate()
        recordEditorDraftChange(coalescingToken: "trim-end")
    }

    func setShouldCrop(_ shouldCrop: Bool) {
        self.shouldCrop = shouldCrop
        recordEditorDraftChange()
    }

    func undoEditorChange() {
        guard let state = editorUndoStack.undo() else {
            return
        }

        applyEditorDraftState(state)
    }

    func redoEditorChange() {
        guard let state = editorUndoStack.redo() else {
            return
        }

        applyEditorDraftState(state)
    }

    func togglePlayback() {
        guard hasSource else {
            return
        }

        if playbackRequested {
            player.pause()
            playbackRequested = false
        } else {
            seekPlaybackIntoTrimRangeIfNeeded()
            player.rate = Float(playbackSpeed.value)
            playbackRequested = true
        }
    }

}
