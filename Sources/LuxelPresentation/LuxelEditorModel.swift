import AVKit
import Foundation
import LuxelCore
import Observation

public enum LuxelEditorScene {
    public static let id = "editor"
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
        case exported(URL)
        case saved(URL)
        case canceled
        case failed(String)
    }

    static let supportedFormats = ExportFormat.appleNativeV1Formats
    static let sizePresets = EditorSizePreset.allCases

    var source: SourceMedia?
    var status: Status = .empty
    var format: ExportFormat = .mp4
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval = 1
    var sizePreset: EditorSizePreset? = .original
    var outputWidth = 1280
    var outputHeight = 720
    var frameRate = 30
    var shouldMute = false
    var shouldCrop = true
    var outputDirectory = LuxelEditorModel.defaultRecordingsDirectory
    var exportProgress: ExportProgressSnapshot?

    @ObservationIgnored var player = AVPlayer()
    @ObservationIgnored private let metadataReader: any MediaMetadataReader
    @ObservationIgnored private let exportService: ExportService
    @ObservationIgnored private let passthroughExportService: PassthroughExportService
    @ObservationIgnored private let fileWorkflowService: ExportedFileWorkflowService
    @ObservationIgnored private var playbackRequested = false
    @ObservationIgnored private var playbackTimeObserver: PlaybackTimeObserver?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    public init(
        metadataReader: any MediaMetadataReader = AVFoundationMediaMetadataReader(),
        exportService: ExportService = ExportService(
            exporter: NativeMediaExporter(),
            fileSystem: LocalFileSystem()
        ),
        passthroughExportService: PassthroughExportService = PassthroughExportService(
            fileSystem: LocalFileSystem()
        ),
        fileWorkflowService: ExportedFileWorkflowService = ExportedFileWorkflowService(
            client: AppKitExportedFileActionClient()
        )
    ) {
        self.metadataReader = metadataReader
        self.exportService = exportService
        self.passthroughExportService = passthroughExportService
        self.fileWorkflowService = fileWorkflowService
        player.actionAtItemEnd = .none
        installPlaybackLoopObserver()
    }

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

    var includesAudio: Bool {
        canIncludeAudio && !shouldMute
    }

    var isExporting: Bool {
        status == .exporting || status == .savingOriginal
    }

    var canExport: Bool {
        hasSource && !isExporting
    }

    var canSaveOriginal: Bool {
        hasSource && !isExporting
    }

    var canCancelExport: Bool {
        isExporting && exportTask != nil
    }

    var canRetryExport: Bool {
        hasSource && !isExporting
    }

    var showsExportProgressPanel: Bool {
        isExporting || exportProgress != nil || exportedURL != nil || status == .canceled || isRecoverableExportFailure
    }

    var exportPanelTitle: String {
        switch status {
        case .exporting, .savingOriginal:
            exportProgressTitle
        case .exported, .saved:
            "Export Complete"
        case .canceled:
            "Export Canceled"
        case .failed:
            "Export Failed"
        case .empty, .loading, .ready:
            exportProgressTitle
        }
    }

    var exportPanelMessage: String {
        switch status {
        case .exported(let url), .saved(let url):
            url.lastPathComponent
        case .savingOriginal:
            "Copying the source recording without re-encoding."
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
        case .exported, .saved:
            "checkmark.circle"
        case .canceled:
            "xmark.circle"
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

    var exportedURL: URL? {
        if case .exported(let url) = status {
            return url
        }

        if case .saved(let url) = status {
            return url
        }

        return nil
    }

    var sourceSummary: String {
        guard let source else {
            return "No recording loaded"
        }

        let audio = source.hasAudio ? "audio" : "no audio"
        return "\(source.fileURL.lastPathComponent) | \(formatTime(source.duration)) | \(source.pixelSize.width)x\(source.pixelSize.height) | \(audio)"
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
            "Exporting \(format.prettyName)"
        case .savingOriginal:
            "Saving original"
        case .exported(let url):
            "Exported \(url.lastPathComponent)"
        case .saved(let url):
            "Saved \(url.lastPathComponent)"
        case .canceled:
            "Export canceled"
        case .failed(let message):
            message
        }
    }

    public func open(fileURL: URL, outputDirectory: URL) async {
        self.outputDirectory = outputDirectory
        status = .loading(fileURL.lastPathComponent)
        exportProgress = nil
        player.pause()
        playbackRequested = false

        do {
            let media = try await metadataReader.readSourceMedia(at: fileURL)
            source = media
            trimStart = 0
            trimEnd = media.duration
            setSizePreset(.original)
            setFrameRate(media.nominalFrameRate.framesPerSecond)
            shouldMute = !media.hasAudio || format.dropsAudio
            player.replaceCurrentItem(with: AVPlayerItem(url: fileURL))
            status = .ready
        } catch {
            source = nil
            player.replaceCurrentItem(with: nil)
            status = .failed(errorMessage(error))
        }
    }

    public func reportImportFailure(_ error: Error) {
        source = nil
        exportProgress = nil
        player.replaceCurrentItem(with: nil)
        status = .failed(errorMessage(error))
    }

    func setFormat(_ nextFormat: ExportFormat) {
        format = nextFormat

        if !canIncludeAudio {
            shouldMute = true
        }

        exportProgress = nil
    }

    func setIncludesAudio(_ includesAudio: Bool) {
        shouldMute = !includesAudio
    }

    func setSizePreset(_ preset: EditorSizePreset?) {
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

    func setOutputWidth(_ value: Int) {
        outputWidth = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
    }

    func setOutputHeight(_ value: Int) {
        outputHeight = clampedPixelDimension(value)
        updateSizePresetFromDimensions()
    }

    func setFrameRate(_ value: Int) {
        frameRate = min(max(value, 1), maximumFrameRate)
    }

    func setTrimStart(_ value: TimeInterval) {
        let maxStart = max(0, min(duration - minimumTrimDuration, trimEnd - minimumTrimDuration))
        trimStart = min(max(value, 0), maxStart)
        seekPlaybackIntoTrimRangeIfNeeded()
    }

    func setTrimEnd(_ value: TimeInterval) {
        let minEnd = min(duration, trimStart + minimumTrimDuration)
        trimEnd = min(max(value, minEnd), duration)
        seekPlaybackIntoTrimRangeIfNeeded()
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
            player.play()
            playbackRequested = true
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
        exportProgress = .preparing(format: format)

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let draft = EditorExportDraft(
                source: source,
                format: format,
                trimRange: try TimeRange(start: trimStart, end: trimEnd),
                pixelSize: try PixelSize(width: outputWidth, height: outputHeight),
                frameRate: try FrameRate(frameRate),
                shouldMute: shouldMute,
                shouldCrop: shouldCrop
            )
            let exportService = exportService
            let outputDirectory = outputDirectory
            let defaultName = defaultExportName(for: source.fileURL)

            exportTask = Task { [weak self] in
                do {
                    let exported = try await exportService.export(
                        draft,
                        to: outputDirectory,
                        defaultName: defaultName
                    ) { snapshot in
                        await MainActor.run {
                            self?.exportProgress = snapshot
                        }
                    }

                    await MainActor.run {
                        self?.finishExport(with: exported)
                    }
                } catch is CancellationError {
                    await MainActor.run {
                        self?.finishCanceledExport(format: draft.format)
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

    private func finishExport(with exported: ExportedMedia) {
        exportTask = nil
        exportProgress = .completed(format: exported.format)
        status = .exported(exported.fileURL)
    }

    private func finishSavedOriginal(_ fileURL: URL) {
        exportTask = nil
        exportProgress = nil
        status = .saved(fileURL)
    }

    private func finishCanceledExport(format: ExportFormat) {
        exportTask = nil
        exportProgress = .canceled(format: format)
        status = .canceled
    }

    private func finishFailedExport(_ error: Error) {
        exportTask = nil
        exportProgress = nil
        status = .failed(errorMessage(error))
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

    private func errorMessage(_ error: Error) -> String {
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
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
