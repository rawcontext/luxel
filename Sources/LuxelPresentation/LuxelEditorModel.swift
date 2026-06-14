import AVKit
import Foundation
import LuxelCore
import Observation

public enum LuxelEditorScene {
    public static let id = "editor"
}

enum EditorGIFLoopModeKind: String, CaseIterable, Equatable, Hashable {
    case forever
    case none
    case count
    case bounce

    var label: String {
        switch self {
        case .forever:
            "Forever"
        case .none:
            "Off"
        case .count:
            "Count"
        case .bounce:
            "Bounce"
        }
    }
}

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
    private var editorUndoStack = UndoStack(initialState: EditorDraftState.defaults)

    @ObservationIgnored var player = AVPlayer()
    @ObservationIgnored private let metadataReader: any MediaMetadataReader
    @ObservationIgnored private let exportService: ExportService
    @ObservationIgnored private let exportSizeEstimationService: ExportSizeEstimationService
    @ObservationIgnored private let passthroughExportService: PassthroughExportService
    @ObservationIgnored private let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored private let frameGrabService: FrameGrabService
    @ObservationIgnored private let fileSystem: any FileSystem
    @ObservationIgnored private var playbackRequested = false
    @ObservationIgnored private var playbackTimeObserver: PlaybackTimeObserver?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var frameGrabTask: Task<Void, Never>?
    @ObservationIgnored private var exportMemoryByFormat: [ExportFormat: ExportMemory]
    @ObservationIgnored private var onExportMemoryChange: (@MainActor (ExportFormat, ExportMemory) -> Void)?
    @ObservationIgnored private var onConfirmDiscardChange: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var onDiscardRecording: (@MainActor (URL) -> Void)?

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
        self.fileSystem = fileSystem
        self.supportedFormats = codecAvailability.availableExportFormats
        self.exportMemoryByFormat = exportMemory
        self.onExportMemoryChange = onExportMemoryChange
        player.actionAtItemEnd = .none
        installPlaybackLoopObserver()
    }

    public var confirmDiscard = true

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
            status = .ready
            resetEditorUndoStack()
        } catch {
            source = nil
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
        recordEditorDraftChange(coalescingToken: "trim-start")
    }

    func setTrimEnd(_ value: TimeInterval) {
        let minEnd = min(duration, trimStart + minimumTrimDuration)
        trimEnd = min(max(value, minEnd), duration)
        seekPlaybackIntoTrimRangeIfNeeded()
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

    func refreshExportEstimate() async {
        guard let source else {
            exportEstimate = nil
            isEstimatingExportSize = false
            return
        }

        let taskID = exportEstimateTaskID
        isEstimatingExportSize = true
        defer {
            if exportEstimateTaskID == taskID {
                isEstimatingExportSize = false
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(300))
            let draft = try makeExportDraft(source: source)
            let estimate = try await exportSizeEstimationService.estimate(draft)

            guard !Task.isCancelled, exportEstimateTaskID == taskID else {
                return
            }

            exportEstimate = estimate
        } catch is CancellationError {
            return
        } catch {
            exportEstimate = nil
        }
    }

    func startExport() {
        guard let source else {
            return
        }

        guard exportTask == nil else {
            return
        }

        status = .exporting
        let selectedFormats = selectedFormats
        exportJobs = makeExportJobs(for: selectedFormats)
        exportProgress = .preparing(format: format)

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let exportRequests = try selectedFormats.map { selectedFormat in
                try makeExportRequest(source: source, format: selectedFormat)
            }
            let exportMemoryByFormat = try Dictionary(
                uniqueKeysWithValues: selectedFormats.map { selectedFormat in
                    (selectedFormat, try currentExportMemory(for: selectedFormat))
                }
            )
            let exportService = exportService
            let outputDirectory = outputDirectory
            let defaultName = defaultExportName(for: source.fileURL)

            exportTask = Task { [weak self] in
                do {
                    if exportRequests.count == 1, let request = exportRequests.first {
                        let exported = try await exportService.export(
                            request,
                            to: outputDirectory,
                            defaultName: defaultName
                        ) { snapshot in
                            await MainActor.run {
                                self?.handleSingleExportProgress(snapshot)
                            }
                        }

                        await MainActor.run {
                            self?.finishExport(
                                with: exported,
                                remembering: exportMemoryByFormat[exported.format]
                            )
                        }
                    } else {
                        let batch = try ExportBatch(exportRequests)
                        let exported = try await exportService.runBatch(
                            batch,
                            to: outputDirectory,
                            defaultName: defaultName
                        ) { snapshot in
                            await MainActor.run {
                                self?.handleBatchExportProgress(snapshot)
                            }
                        }

                        await MainActor.run {
                            self?.finishBatchExport(
                                with: exported,
                                remembering: exportMemoryByFormat
                            )
                        }
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.finishCanceledExport()
                    }
                } catch {
                    await MainActor.run {
                        self?.finishFailedExport(error)
                    }
                }
            }
        } catch {
            status = .failed(errorMessage(error))
            exportProgress = nil
        }
    }

    func saveOriginal() {
        guard let source else {
            return
        }

        guard exportTask == nil else {
            return
        }

        status = .savingOriginal
        exportProgress = nil

        let passthroughExportService = passthroughExportService
        let request = PassthroughExportRequest(
            inputFileURL: source.fileURL,
            outputFileURL: originalOutputURL(for: source.fileURL)
        )

        exportTask = Task { [weak self] in
            do {
                let result = try await passthroughExportService.export(request)

                await MainActor.run {
                    self?.finishSavedOriginal(result.fileURL)
                }
            } catch {
                await MainActor.run {
                    self?.finishFailedExport(error)
                }
            }
        }
    }

    func copyCurrentFrame() {
        guard canGrabFrame else {
            return
        }

        startFrameGrab(destinations: [.clipboard])
    }

    func saveCurrentFrameAs() {
        guard canGrabFrame else {
            return
        }

        do {
            let request = try makeCurrentFrameGrabRequest()
            guard let destinationURL = fileWorkflowService.chooseSaveDestination(
                suggestedFileName: request.suggestedFileName
            ) else {
                return
            }

            startFrameGrab(
                request: request,
                destinations: [.file],
                outputFileURL: destinationURL
            )
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    @discardableResult
    func discardRecording() -> Bool {
        guard canDiscard, let source else {
            return false
        }

        do {
            let fileURL = source.fileURL
            try fileSystem.trashItem(at: fileURL)
            clearSource()
            status = .discarded(fileURL.lastPathComponent)
            onDiscardRecording?(fileURL)
            return true
        } catch {
            status = .failed(errorMessage(error))
            return false
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func retryExport() {
        guard canRetryExport else {
            return
        }

        startExport()
    }

    func chooseOutputDirectory() {
        guard let directory = fileWorkflowService.chooseOutputDirectory(currentDirectory: outputDirectory) else {
            return
        }

        outputDirectory = directory
    }

    func saveExportedFileAs() {
        guard let exportedURL else {
            return
        }

        do {
            if let savedURL = try fileWorkflowService.saveAs(exportedURL) {
                status = .saved(savedURL)
            }
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func revealExportedFile() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.revealInFinder(exportedURL)
    }

    func openExportedFile() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.openWithDefaultApp(exportedURL)
    }

    func openExportedFileWithApplication() {
        guard let exportedURL else {
            return
        }

        _ = fileWorkflowService.openWithApplication(exportedURL)
    }

    func copyExportedFilePath() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.copyPath(exportedURL)
    }

    func copyExportedFile() {
        guard let exportedURL else {
            return
        }

        fileWorkflowService.copyFile(exportedURL)
    }

    func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func defaultExportName(for fileURL: URL) -> String {
        "\(fileURL.deletingPathExtension().lastPathComponent) Export"
    }

    private func originalOutputURL(for fileURL: URL) -> URL {
        let baseName = "\(fileURL.deletingPathExtension().lastPathComponent) Original"
        let fileExtension = fileURL.pathExtension
        let outputURL = outputDirectory.appending(path: baseName)

        guard !fileExtension.isEmpty else {
            return outputURL
        }

        return outputURL.appendingPathExtension(fileExtension)
    }

    private static var defaultRecordingsDirectory: URL {
        let moviesDirectory = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

    private func handleSingleExportProgress(_ snapshot: ExportProgressSnapshot) {
        exportProgress = snapshot
        updateExportJob(id: 0, snapshot: snapshot)
    }

    private func handleBatchExportProgress(_ batchSnapshot: ExportBatchProgressSnapshot) {
        updateExportJob(id: batchSnapshot.jobID, snapshot: batchSnapshot.snapshot)

        let jobCount = max(exportJobs.count, 1)
        let progress = (Double(batchSnapshot.jobID) + batchSnapshot.snapshot.progress) / Double(jobCount)
        exportProgress = ExportProgressSnapshot(
            phase: batchSnapshot.snapshot.phase,
            actionTitle: batchSnapshot.snapshot.actionTitle,
            progress: progress
        )
    }

    private func finishExport(with exported: ExportedMedia, remembering exportMemory: ExportMemory?) {
        exportTask = nil
        if let exportMemory {
            rememberExportMemory(exportMemory, for: exported.format)
        }
        updateExportJob(id: 0, exported: exported)
        exportProgress = .completed(format: exported.format)
        status = .exported(exported.fileURL)
    }

    private func finishBatchExport(
        with exportedMedia: [ExportedMedia],
        remembering exportMemoryByFormat: [ExportFormat: ExportMemory]
    ) {
        exportTask = nil

        for exported in exportedMedia {
            if let exportMemory = exportMemoryByFormat[exported.format] {
                rememberExportMemory(exportMemory, for: exported.format)
            }
            updateExportJob(format: exported.format, exported: exported)
        }

        exportProgress = ExportProgressSnapshot(
            phase: .completed,
            actionTitle: "Exported \(exportedMedia.count) files",
            progress: 1
        )
        status = .exportedBatch(exportedMedia.map(\.fileURL))
    }

    private func finishSavedOriginal(_ fileURL: URL) {
        exportTask = nil
        exportProgress = nil
        exportJobs = []
        status = .saved(fileURL)
    }

    private func finishCanceledExport() {
        exportTask = nil
        if exportProgress?.phase != .canceled {
            exportProgress = ExportProgressSnapshot(
                phase: .canceled,
                actionTitle: "Canceled Export",
                progress: 1
            )
        }
        status = .canceled
    }

    private func finishFailedExport(_ error: Error) {
        exportTask = nil
        exportProgress = nil
        status = .failed(errorMessage(error))
    }

    private func startFrameGrab(destinations: [ScreenshotDestination]) {
        do {
            try startFrameGrab(
                request: makeCurrentFrameGrabRequest(),
                destinations: destinations
            )
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    private func startFrameGrab(
        request: FrameGrabRequest,
        destinations: [ScreenshotDestination],
        outputFileURL: URL? = nil
    ) {
        do {
            let job = try FrameGrabJob(
                request: request,
                destinations: destinations,
                outputFileURL: outputFileURL
            )
            let frameGrabService = frameGrabService
            status = destinations.contains(.clipboard) ? .copyingFrame : .savingFrame

            frameGrabTask = Task { [weak self] in
                do {
                    let result = try await frameGrabService.grab(job)
                    await MainActor.run {
                        self?.finishFrameGrab(result)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.finishCanceledFrameGrab()
                    }
                } catch {
                    await MainActor.run {
                        self?.finishFailedFrameGrab(error)
                    }
                }
            }
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    private func finishFrameGrab(_ result: FrameGrabResult) {
        frameGrabTask = nil

        if !result.failedDestinations.isEmpty {
            status = .failed("Frame destination failed")
            return
        }

        if let fileURL = result.fileURL {
            status = .savedFrame(fileURL)
        } else if result.completedDestinations.contains(.clipboard) {
            status = .copiedFrame
        } else {
            status = .ready
        }
    }

    private func finishCanceledFrameGrab() {
        frameGrabTask = nil
        status = .ready
    }

    private func finishFailedFrameGrab(_ error: Error) {
        frameGrabTask = nil
        status = .failed(errorMessage(error))
    }

    private func makeCurrentFrameGrabRequest() throws -> FrameGrabRequest {
        guard let source else {
            throw ScreenshotModelError.invalidFrameTime
        }

        return try FrameGrabRequest(
            sourceFileURL: source.fileURL,
            time: currentFrameTime,
            format: .png
        )
    }

    private var currentFrameTime: TimeInterval {
        let seconds = CMTimeGetSeconds(player.currentTime())
        let finiteSeconds = seconds.isFinite ? seconds : trimStart
        return min(max(finiteSeconds, 0), max(duration, 0))
    }

    private func clearSource() {
        source = nil
        exportProgress = nil
        exportJobs = []
        exportEstimate = nil
        isEstimatingExportSize = false
        frameGrabTask?.cancel()
        frameGrabTask = nil
        player.pause()
        playbackRequested = false
        player.replaceCurrentItem(with: nil)
        resetEditorUndoStack()
    }

    private func makeExportJobs(for formats: [ExportFormat]) -> [ExportJobSnapshot] {
        formats.enumerated().map { index, format in
            ExportJobSnapshot(id: index, format: format)
        }
    }

    private func updateExportJob(id: Int, snapshot: ExportProgressSnapshot) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].progress = snapshot
    }

    private func updateExportJob(id: Int, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    private func updateExportJob(format: ExportFormat, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.format == format }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    private func installPlaybackLoopObserver() {
        guard playbackTimeObserver == nil else {
            return
        }

        playbackTimeObserver = PlaybackTimeObserver(player: player) { [weak self] seconds in
            self?.handlePlaybackTime(seconds)
        }
    }

    private func handlePlaybackTime(_ currentTime: TimeInterval) {
        guard playbackRequested else {
            return
        }

        seekPlaybackIntoTrimRangeIfNeeded(currentTime: currentTime)
    }

    private func seekPlaybackIntoTrimRangeIfNeeded(currentTime: TimeInterval? = nil) {
        guard let loop = playbackLoop else {
            return
        }

        let seconds = currentTime ?? CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, let target = loop.seekTarget(for: seconds) else {
            return
        }

        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private var playbackLoop: EditorPlaybackLoop? {
        guard let trimRange = try? TimeRange(start: trimStart, end: trimEnd) else {
            return nil
        }

        return EditorPlaybackLoop(trimRange: trimRange)
    }

    func revealExportJob(_ job: ExportJobSnapshot) {
        guard let fileURL = job.fileURL else {
            return
        }

        fileWorkflowService.revealInFinder(fileURL)
    }

    private var isRecoverableExportFailure: Bool {
        if case .failed = status {
            return hasSource
        }

        return false
    }

    private func clampedPixelDimension(_ value: Int) -> Int {
        min(max(value, 1), 8192)
    }

    private func updateSizePresetFromDimensions() {
        guard let source, let currentPixelSize = try? PixelSize(width: outputWidth, height: outputHeight) else {
            sizePreset = nil
            return
        }

        sizePreset = Self.sizePresets.first { preset in
            (try? preset.pixelSize(for: source.pixelSize)) == currentPixelSize
        }
    }

    private func applySizePreset(_ preset: EditorSizePreset?) {
        sizePreset = preset

        guard let preset, let source else {
            return
        }

        do {
            let pixelSize = try preset.pixelSize(for: source.pixelSize)
            outputWidth = pixelSize.width
            outputHeight = pixelSize.height
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    private func applyFrameRate(_ value: Int) {
        frameRate = min(max(value, 1), maximumFrameRate)
    }

    private func applyExportMemory(for format: ExportFormat) {
        guard let memory = exportMemoryByFormat[format] else {
            if !quality.isAvailable(for: format) {
                quality = ExportQuality.defaultQuality(for: format)
            }
            return
        }

        applySizePreset(memory.sizePreset)
        applyFrameRate(memory.frameRate.framesPerSecond)
        quality = memory.quality.isAvailable(for: format)
            ? memory.quality
            : ExportQuality.defaultQuality(for: format)
        if format == .gif, let gifOptions = memory.gifOptions {
            applyGIFOptions(gifOptions)
        }
    }

    private func applyGIFOptions(_ options: GIFRenderOptions) {
        gifDithering = options.dithering

        switch options.loopMode {
        case .forever:
            gifLoopModeKind = .forever
        case .none:
            gifLoopModeKind = .none
        case .count(let count):
            gifLoopModeKind = .count
            gifLoopCount = min(max(count, 1), 100)
        case .bounce:
            gifLoopModeKind = .bounce
        }
    }

    private func recordEditorDraftChange(coalescingToken: String? = nil) {
        guard hasSource else {
            return
        }

        editorUndoStack.push(currentEditorDraftState, coalescingToken: coalescingToken)
        exportProgress = nil
    }

    private var currentEditorDraftState: EditorDraftState {
        EditorDraftState(
            format: format,
            selectedFormats: selectedFormats,
            trimStart: trimStart,
            trimEnd: trimEnd,
            sizePreset: sizePreset,
            outputWidth: outputWidth,
            outputHeight: outputHeight,
            frameRate: frameRate,
            playbackSpeed: playbackSpeed,
            shouldMute: shouldMute,
            shouldCrop: shouldCrop,
            quality: quality,
            gifLoopModeKind: gifLoopModeKind,
            gifLoopCount: gifLoopCount,
            gifDithering: gifDithering
        )
    }

    private func resetEditorUndoStack() {
        editorUndoStack = UndoStack(initialState: currentEditorDraftState)
    }

    private func applyEditorDraftState(_ state: EditorDraftState) {
        let fallbackFormat = supportedFormats.first ?? .mp4
        let restoredFormat = supportedFormats.contains(state.format) ? state.format : fallbackFormat
        let restoredFormats = supportedFormats.filter(state.selectedFormats.contains)

        format = restoredFormat
        selectedFormats = restoredFormats.isEmpty ? [restoredFormat] : restoredFormats
        if !selectedFormats.contains(format) {
            format = selectedFormats.first ?? fallbackFormat
        }
        trimStart = state.trimStart
        trimEnd = state.trimEnd
        sizePreset = state.sizePreset
        outputWidth = state.outputWidth
        outputHeight = state.outputHeight
        frameRate = min(max(state.frameRate, 1), maximumFrameRate)
        playbackSpeed = state.playbackSpeed
        applyPlaybackRateIfNeeded()
        quality = state.quality.isAvailable(for: format)
            ? state.quality
            : ExportQuality.defaultQuality(for: format)
        gifLoopModeKind = state.gifLoopModeKind
        gifLoopCount = min(max(state.gifLoopCount, 1), 100)
        gifDithering = state.gifDithering
        shouldMute = state.shouldMute
        if !canIncludeAudio {
            shouldMute = true
        }
        shouldCrop = state.shouldCrop
        exportProgress = nil
        seekPlaybackIntoTrimRangeIfNeeded()
    }

    private func currentExportMemory(for format: ExportFormat) throws -> ExportMemory {
        ExportMemory(
            sizePreset: sizePreset ?? .original,
            frameRate: try FrameRate(frameRate),
            quality: quality.isAvailable(for: format) ? quality : ExportQuality.defaultQuality(for: format),
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    private func rememberExportMemory(_ memory: ExportMemory, for format: ExportFormat) {
        exportMemoryByFormat[format] = memory
        onExportMemoryChange?(format, memory)
    }

    private func makeExportDraft(source: SourceMedia) throws -> EditorExportDraft {
        try EditorExportDraft(
            source: source,
            format: format,
            trimRange: TimeRange(start: trimStart, end: trimEnd),
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            shouldMute: shouldMute,
            shouldCrop: shouldCrop,
            quality: quality,
            speed: playbackSpeed,
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    private func makeExportRequest(source: SourceMedia, format: ExportFormat) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: source.fileURL,
            format: format,
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            timeRange: TimeRange(start: trimStart, end: trimEnd),
            shouldMute: shouldMute,
            shouldCrop: shouldCrop,
            quality: quality,
            speed: playbackSpeed,
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    private func currentGIFOptions(for format: ExportFormat) throws -> GIFRenderOptions? {
        guard format == .gif else {
            return nil
        }

        let resolvedQuality = quality.isAvailable(for: format)
            ? quality
            : ExportQuality.defaultQuality(for: format)
        return try GIFRenderOptions(
            quality: resolvedQuality,
            loopMode: gifLoopMode,
            dithering: gifDithering
        )
    }

    private func applyPlaybackRateIfNeeded() {
        guard playbackRequested else {
            return
        }

        player.rate = Float(playbackSpeed.value)
    }

    private func errorMessage(_ error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }
}

private struct EditorDraftState: Equatable, Sendable {
    static let defaults = EditorDraftState(
        format: .mp4,
        selectedFormats: [.mp4],
        trimStart: 0,
        trimEnd: 1,
        sizePreset: .original,
        outputWidth: 1280,
        outputHeight: 720,
        frameRate: 30,
        playbackSpeed: .normal,
        shouldMute: false,
        shouldCrop: true,
        quality: .balanced,
        gifLoopModeKind: .forever,
        gifLoopCount: 3,
        gifDithering: .auto
    )

    let format: ExportFormat
    let selectedFormats: [ExportFormat]
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let sizePreset: EditorSizePreset?
    let outputWidth: Int
    let outputHeight: Int
    let frameRate: Int
    let playbackSpeed: PlaybackSpeed
    let shouldMute: Bool
    let shouldCrop: Bool
    let quality: ExportQuality
    let gifLoopModeKind: EditorGIFLoopModeKind
    let gifLoopCount: Int
    let gifDithering: GIFDitheringMode
}

struct ExportEstimateTaskID: Equatable, Hashable {
    let sourceFileURL: URL
    let format: ExportFormat
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let outputWidth: Int
    let outputHeight: Int
    let frameRate: Int
    let playbackSpeed: Double
    let quality: ExportQuality
    let gifLoopModeKind: EditorGIFLoopModeKind?
    let gifLoopCount: Int?
    let gifDithering: GIFDitheringMode?
    let shouldMute: Bool
    let shouldCrop: Bool
}

struct ExportJobSnapshot: Identifiable, Equatable {
    let id: Int
    let format: ExportFormat
    var progress: ExportProgressSnapshot?
    var fileURL: URL?
    var fileSizeBytes: Int64?

    var progressValue: Double {
        progress?.progress ?? 0
    }

    var statusSummary: String {
        if let fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
        }

        guard let progress else {
            return "Queued"
        }

        switch progress.phase {
        case .preparing:
            return "Preparing"
        case .exporting:
            return "\(Int((progress.progress * 100).rounded()))%"
        case .completed:
            return "Complete"
        case .canceled:
            return "Canceled"
        }
    }
}

private final class PlaybackTimeObserver {
    private let player: AVPlayer
    private let token: Any

    init(player: AVPlayer, onTick: @escaping @MainActor @Sendable (TimeInterval) -> Void) {
        self.player = player
        token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600),
            queue: .main
        ) { time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else {
                return
            }

            Task { @MainActor in
                onTick(seconds)
            }
        }
    }

    deinit {
        player.removeTimeObserver(token)
    }
}
