import AVKit
import Foundation
import LuxelCore
import Observation

extension LuxelEditorModel {
    func navigateToOlderRecording() async {
        guard let recordingNavigationIndex,
              canNavigateToOlderRecording
        else {
            return
        }

        await openRecordingNavigationItem(at: recordingNavigationIndex + 1)
    }

    func navigateToNewerRecording() async {
        guard let recordingNavigationIndex,
              canNavigateToNewerRecording
        else {
            return
        }

        await openRecordingNavigationItem(at: recordingNavigationIndex - 1)
    }

    private func openRecordingNavigationItem(at index: Int) async {
        guard recordingNavigationURLs.indices.contains(index) else {
            return
        }

        await open(
            fileURL: recordingNavigationURLs[index],
            outputDirectory: outputDirectory,
            outputDirectoryBookmark: outputDirectoryBookmark
        )
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
            let outputDirectoryBookmark = outputDirectoryBookmark
            let directoryAccessService = directoryAccessService
            let defaultName = defaultExportName(for: source.fileURL)
            let fileSystem = fileSystem

            exportTask = Task { [weak self] in
                do {
                    try await withExportDirectoryAccess(
                        outputDirectory: outputDirectory,
                        bookmark: outputDirectoryBookmark,
                        directoryAccessService: directoryAccessService
                    ) { resolvedOutputDirectory in
                        let exportOutputDirectory: URL
                        if exportRequests.count > 1 {
                            exportOutputDirectory = editorBatchOutputDirectory(
                                defaultName: defaultName,
                                in: resolvedOutputDirectory
                            )
                        } else {
                            exportOutputDirectory = resolvedOutputDirectory
                        }

                        try fileSystem.createDirectory(at: exportOutputDirectory)

                        if exportRequests.count == 1, let request = exportRequests.first {
                            let exported = try await exportService.export(
                                request,
                                to: exportOutputDirectory,
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
                                to: exportOutputDirectory,
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
        let inputFileURL = source.fileURL
        let outputDirectory = outputDirectory
        let outputDirectoryBookmark = outputDirectoryBookmark
        let directoryAccessService = directoryAccessService

        exportTask = Task { [weak self] in
            do {
                try await withExportDirectoryAccess(
                    outputDirectory: outputDirectory,
                    bookmark: outputDirectoryBookmark,
                    directoryAccessService: directoryAccessService
                ) { resolvedOutputDirectory in
                    let request = PassthroughExportRequest(
                        inputFileURL: inputFileURL,
                        outputFileURL: editorOriginalOutputURL(for: inputFileURL, in: resolvedOutputDirectory)
                    )
                    let result = try await passthroughExportService.export(request)

                    await MainActor.run {
                        self?.finishSavedOriginal(result.fileURL)
                    }
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
            guard
                let destinationURL = fileWorkflowService.chooseSaveDestination(
                    suggestedFileName: request.suggestedFileName
                )
            else {
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
        guard
            let directory = fileWorkflowService.chooseOutputDirectory(currentDirectory: outputDirectory)
        else {
            return
        }

        outputDirectory = directory
        outputDirectoryBookmark = nil
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

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.revealInFinder(exportedURL)
        }
    }

    func openExportedFile() {
        guard let exportedOpenURL else {
            return
        }

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.openWithDefaultApp(exportedOpenURL)
        }
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

    func defaultExportName(for fileURL: URL) -> String {
        "\(fileURL.deletingPathExtension().lastPathComponent) Export"
    }

    func batchOutputDirectory(defaultName: String, in outputDirectory: URL) -> URL {
        editorBatchOutputDirectory(defaultName: defaultName, in: outputDirectory)
    }

    func originalOutputURL(for fileURL: URL) -> URL {
        editorOriginalOutputURL(for: fileURL, in: outputDirectory)
    }

    static var defaultRecordingsDirectory: URL {
        let moviesDirectory =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appending(path: "Movies")

        return moviesDirectory.appending(path: "Luxel")
    }

    func handleSingleExportProgress(_ snapshot: ExportProgressSnapshot) {
        exportProgress = snapshot
        updateExportJob(id: 0, snapshot: snapshot)
    }

    func handleBatchExportProgress(_ batchSnapshot: ExportBatchProgressSnapshot) {
        updateExportJob(id: batchSnapshot.jobID, snapshot: batchSnapshot.snapshot)

        let jobCount = max(exportJobs.count, 1)
        let progress =
            (Double(batchSnapshot.jobID) + batchSnapshot.snapshot.progress) / Double(jobCount)
        exportProgress = ExportProgressSnapshot(
            phase: batchSnapshot.snapshot.phase,
            actionTitle: batchSnapshot.snapshot.actionTitle,
            progress: progress
        )
    }

    func finishExport(with exported: ExportedMedia, remembering exportMemory: ExportMemory?) {
        exportTask = nil
        if let exportMemory {
            rememberExportMemory(exportMemory, for: exported.format)
        }
        updateExportJob(id: 0, exported: exported)
        exportProgress = .completed(format: exported.format)
        status = .exported(exported.fileURL)
    }

    func finishBatchExport(
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

    func finishSavedOriginal(_ fileURL: URL) {
        exportTask = nil
        exportProgress = nil
        exportJobs = []
        status = .saved(fileURL)
    }

    func finishCanceledExport() {
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

    func finishFailedExport(_ error: Error) {
        exportTask = nil
        exportProgress = nil
        status = .failed(errorMessage(error))
    }

    func startFrameGrab(destinations: [FrameGrabDestination]) {
        do {
            try startFrameGrab(
                request: makeCurrentFrameGrabRequest(),
                destinations: destinations
            )
        } catch {
            status = .failed(errorMessage(error))
        }
    }

    func startFrameGrab(
        request: FrameGrabRequest,
        destinations: [FrameGrabDestination],
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

    func finishFrameGrab(_ result: FrameGrabResult) {
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

    func finishCanceledFrameGrab() {
        frameGrabTask = nil
        status = .ready
    }

    func finishFailedFrameGrab(_ error: Error) {
        frameGrabTask = nil
        status = .failed(errorMessage(error))
    }

    func makeCurrentFrameGrabRequest() throws -> FrameGrabRequest {
        guard let source else {
            throw FrameGrabError.invalidFrameTime
        }

        return try FrameGrabRequest(
            sourceFileURL: source.fileURL,
            time: currentFrameTime
        )
    }

    var currentFrameTime: TimeInterval {
        let seconds = CMTimeGetSeconds(player.currentTime())
        let finiteSeconds = seconds.isFinite ? seconds : trimStart
        return min(max(finiteSeconds, 0), max(duration, 0))
    }

    func clearSource() {
        source = nil
        recordingNavigationIndex = nil
        exportProgress = nil
        exportJobs = []
        exportEstimate = nil
        isEstimatingExportSize = false
        frameGrabTask?.cancel()
        frameGrabTask = nil
        previewAudioMixTask?.cancel()
        previewAudioMixTask = nil
        speechRecognitionAuthorizationTask?.cancel()
        speechRecognitionAuthorizationTask = nil
        transcriptTask?.cancel()
        transcriptTask = nil
        transcript = nil
        isTranscriptExtractionActive = false
        speechRecognitionAuthorizationState = nil
        player.pause()
        playbackRequested = false
        currentPlaybackTime = 0
        player.replaceCurrentItem(with: nil)
        resetEditorUndoStack()
    }

    func refreshRecordingNavigation(selectedFileURL: URL, outputDirectory: URL) {
        let selectedFileURL = selectedFileURL.standardizedFileURL
        recordingNavigationURLs = Self.recordingNavigationURLs(
            in: outputDirectory,
            selectedFileURL: selectedFileURL
        )
        recordingNavigationIndex = recordingNavigationURLs.firstIndex {
            $0.standardizedFileURL == selectedFileURL
        }
    }

    private static func recordingNavigationURLs(
        in outputDirectory: URL,
        selectedFileURL: URL
    ) -> [URL] {
        let directoryURLs =
            (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: [
                    .creationDateKey,
                    .contentModificationDateKey,
                    .isRegularFileKey
                ],
                options: [.skipsHiddenFiles]
            )) ?? []

        let recordingURLs =
            (directoryURLs.compactMap(recordingNavigationCandidate)
                + [
                    recordingNavigationCandidate(for: selectedFileURL)
                        ?? (selectedFileURL.standardizedFileURL, .distantPast)
                ])
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.url.lastPathComponent > rhs.url.lastPathComponent
                }

                return lhs.date > rhs.date
            }
            .map(\.url)

        return uniqueNavigationURLs(recordingURLs)
    }

    private static func recordingNavigationCandidate(for url: URL) -> (url: URL, date: Date)? {
        guard isNavigableRecordingURL(url),
              let values = try? url.resourceValues(forKeys: [
                .creationDateKey,
                .contentModificationDateKey,
                .isRegularFileKey
              ]),
              values.isRegularFile == true
        else {
            return nil
        }

        let date =
            [
                values.creationDate,
                values.contentModificationDate
            ].compactMap(\.self).max() ?? .distantPast

        return (url.standardizedFileURL, date)
    }

    private static func isNavigableRecordingURL(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "caf", "flac", "m4a", "m4v", "mov", "mp4", "wav":
            true
        default:
            false
        }
    }

    private static func uniqueNavigationURLs(_ urls: [URL]) -> [URL] {
        var seenPaths: Set<String> = []

        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    func makeExportJobs(for formats: [ExportFormat]) -> [ExportJobSnapshot] {
        formats.enumerated().map { index, format in
            ExportJobSnapshot(id: index, format: format)
        }
    }

    func updateExportJob(id: Int, snapshot: ExportProgressSnapshot) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].progress = snapshot
    }

    func updateExportJob(id: Int, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.id == id }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    func updateExportJob(format: ExportFormat, exported: ExportedMedia) {
        guard let index = exportJobs.firstIndex(where: { $0.format == format }) else {
            return
        }

        exportJobs[index].fileURL = exported.fileURL
        exportJobs[index].fileSizeBytes = exported.fileSizeBytes
        exportJobs[index].progress = .completed(format: exported.format)
    }

    func installPlaybackLoopObserver() {
        guard playbackTimeObserver == nil else {
            return
        }

        playbackTimeObserver = PlaybackTimeObserver(player: player) { [weak self] seconds in
            self?.handlePlaybackTime(seconds)
        }
    }

    func handlePlaybackTime(_ currentTime: TimeInterval) {
        currentPlaybackTime = currentTime

        guard playbackRequested else {
            return
        }

        seekPlaybackIntoTrimRangeIfNeeded(currentTime: currentTime)
    }

    func seekPlaybackIntoTrimRangeIfNeeded(currentTime: TimeInterval? = nil) {
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

    var playbackLoop: EditorPlaybackLoop? {
        guard let trimRange = try? TimeRange(start: trimStart, end: trimEnd) else {
            return nil
        }

        return EditorPlaybackLoop(trimRange: trimRange)
    }

    func revealExportJob(_ job: ExportJobSnapshot) {
        guard let fileURL = job.fileURL else {
            return
        }

        withCurrentOutputDirectoryAccess {
            fileWorkflowService.revealInFinder(fileURL)
        }
    }

    var isRecoverableExportFailure: Bool {
        if case .failed = status {
            return hasSource
        }

        return false
    }

    func clampedPixelDimension(_ value: Int) -> Int {
        min(max(value, 1), 8192)
    }

    func updateSizePresetFromDimensions() {
        guard let source,
              let currentPixelSize = try? PixelSize(width: outputWidth, height: outputHeight)
        else {
            sizePreset = nil
            return
        }

        sizePreset = Self.sizePresets.first { preset in
            (try? preset.pixelSize(for: source.pixelSize)) == currentPixelSize
        }
    }

    func applySizePreset(_ preset: EditorSizePreset?) {
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

    func applyFrameRate(_ value: Int) {
        frameRate = min(max(value, 1), maximumFrameRate)
    }

    func applyExportMemory(for format: ExportFormat) {
        guard let memory = exportMemoryByFormat[format] else {
            if !quality.isAvailable(for: format) {
                quality = ExportQuality.defaultQuality(for: format)
            }
            return
        }

        applySizePreset(memory.sizePreset)
        applyFrameRate(memory.frameRate.framesPerSecond)
        quality =
            memory.quality.isAvailable(for: format)
            ? memory.quality
            : ExportQuality.defaultQuality(for: format)
        if format == .gif || format == .apng, let gifOptions = memory.gifOptions {
            applyGIFOptions(gifOptions)
        }
    }

    func applySupportedFormatForSource() {
        let fallbackFormat = supportedFormats.first ?? .mp4
        if !supportedFormats.contains(format) {
            format = fallbackFormat
        }

        selectedFormats = supportedFormats.filter(selectedFormats.contains)
        if selectedFormats.isEmpty || !selectedFormats.contains(format) {
            selectedFormats = [format]
        }
    }

    func applyGIFOptions(_ options: GIFRenderOptions) {
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

    func recordEditorDraftChange(coalescingToken: String? = nil) {
        guard hasSource else {
            return
        }

        editorUndoStack.push(currentEditorDraftState, coalescingToken: coalescingToken)
        exportProgress = nil
    }

    var currentEditorDraftState: EditorDraftState {
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
            audioVolume: audioVolume,
            normalizeAudio: normalizeAudio,
            shouldCrop: shouldCrop,
            quality: quality,
            gifLoopModeKind: gifLoopModeKind,
            gifLoopCount: gifLoopCount,
            gifDithering: gifDithering
        )
    }

    func resetEditorUndoStack() {
        editorUndoStack = UndoStack(initialState: currentEditorDraftState)
    }

    func applyEditorDraftState(_ state: EditorDraftState) {
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
        quality =
            state.quality.isAvailable(for: format)
            ? state.quality
            : ExportQuality.defaultQuality(for: format)
        gifLoopModeKind = state.gifLoopModeKind
        gifLoopCount = min(max(state.gifLoopCount, 1), 100)
        gifDithering = state.gifDithering
        shouldMute = state.shouldMute
        if hasAudioOnlySource {
            shouldMute = false
        }
        if !canIncludeAudio {
            shouldMute = true
        }
        audioVolume = min(max(state.audioVolume, 0), 2)
        normalizeAudio = state.normalizeAudio
        shouldCrop = state.shouldCrop
        exportProgress = nil
        schedulePreviewAudioMixUpdate()
        seekPlaybackIntoTrimRangeIfNeeded()
    }

    func currentExportMemory(for format: ExportFormat) throws -> ExportMemory {
        ExportMemory(
            sizePreset: sizePreset ?? .original,
            frameRate: try FrameRate(frameRate),
            quality: quality.isAvailable(for: format)
                ? quality : ExportQuality.defaultQuality(for: format),
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    func rememberExportMemory(_ memory: ExportMemory, for format: ExportFormat) {
        exportMemoryByFormat[format] = memory
        onExportMemoryChange?(format, memory)
    }

    func makeExportDraft(source: SourceMedia) throws -> EditorExportDraft {
        try EditorExportDraft(
            source: source,
            format: format,
            trimRange: TimeRange(start: trimStart, end: trimEnd),
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            shouldMute: hasAudioOnlySource ? false : shouldMute,
            audioMix: currentAudioMixPlan(),
            shouldCrop: hasVideoSource && shouldCrop,
            quality: quality,
            speed: playbackSpeed,
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    func makeExportRequest(source: SourceMedia, format: ExportFormat) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: source.fileURL,
            format: format,
            pixelSize: PixelSize(width: outputWidth, height: outputHeight),
            frameRate: FrameRate(frameRate),
            timeRange: TimeRange(start: trimStart, end: trimEnd),
            shouldMute: source.isAudioOnly ? false : shouldMute,
            audioMix: currentAudioMixPlan(),
            shouldCrop: source.hasVideo && shouldCrop,
            quality: quality,
            speed: playbackSpeed,
            gifOptions: try currentGIFOptions(for: format)
        )
    }

    func currentAudioMixPlan() -> AudioMixPlan? {
        guard includesAudio else {
            return nil
        }

        guard audioVolume != 1 || normalizeAudio else {
            return nil
        }

        return AudioMixPlan(
            tracks: [AudioTrackMix(kind: .system, volume: audioVolume)],
            normalizePeak: normalizeAudio
        )
    }

}
