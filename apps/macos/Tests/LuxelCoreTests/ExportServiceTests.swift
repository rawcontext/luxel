import Foundation
import LuxelCore
import Testing

@Suite("Export service")
struct ExportServiceTests {
    @Test("service exports draft to named destination")
    func serviceExportsDraftToNamedDestination() async throws {
        let exporter = ExportServiceSpyMediaExporter()
        let service = ExportService(exporter: exporter)
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let draft = EditorExportDraft(source: source, format: .hevc)

        let result = try await service.export(
            draft,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        )
        let expectedPixelSize = try PixelSize(width: 640, height: 480)

        #expect(result.fileURL.path == "/tmp/exports/Luxel Clip.mp4")
        #expect(result.format == .hevc)
        #expect(result.pixelSize == expectedPixelSize)
        #expect(result.shouldMute == false)

        let captured = await exporter.capturedExport()
        #expect(captured?.request.format == .hevc)
        #expect(captured?.outputFileURL.path == "/tmp/exports/Luxel Clip.mp4")
    }

    @Test("service emits progress snapshots")
    func serviceEmitsProgressSnapshots() async throws {
        let exporter = ExportServiceSpyMediaExporter(reportedProgress: [0.25, 0.75])
        let progress = ExportServiceProgressRecorder()
        let service = ExportService(exporter: exporter)
        let source = try makeSource()
        let draft = EditorExportDraft(source: source, format: .gif)

        _ = try await service.export(
            draft,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        ) { snapshot in
            await progress.append(snapshot)
        }

        let snapshots = await progress.snapshots()

        #expect(
            snapshots == [
                .preparing(format: .gif),
                .exporting(format: .gif, progress: 0),
                .exporting(format: .gif, progress: 0.25),
                .exporting(format: .gif, progress: 0.75),
                .completed(format: .gif)
            ])
    }

    @Test("service records actual output file size")
    func serviceRecordsActualOutputFileSize() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "luxel-export-service-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let exporter = ExportServiceWritingMediaExporter(byteCount: 1_234)
        let service = ExportService(exporter: exporter)

        let exported = try await service.export(
            try makeRequest(format: .mp4),
            to: directory,
            defaultName: "Luxel Clip"
        )

        #expect(exported.fileSizeBytes == 1_234)
    }

    @Test("service removes intended output when export task is canceled")
    func serviceRemovesIntendedOutputWhenExportTaskIsCanceled() async throws {
        let exporter = ExportServiceCancellableMediaExporter()
        let fileSystem = ExportServiceSpyFileSystem()
        let service = ExportService(exporter: exporter, fileSystem: fileSystem)
        let source = try makeSource()
        let draft = EditorExportDraft(source: source, format: .mp4)
        let outputDirectory = URL(fileURLWithPath: "/tmp/exports")
        let expectedOutputURL = outputDirectory.appending(path: "Luxel Clip.mp4")

        let task = Task {
            try await service.export(
                draft,
                to: outputDirectory,
                defaultName: "Luxel Clip"
            )
        }

        await exporter.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(fileSystem.removedURLs == [expectedOutputURL])
    }

    @Test("batch export preserves request order with keyed progress")
    func batchExportPreservesRequestOrderWithKeyedProgress() async throws {
        let exporter = ExportServiceSpyMediaExporter()
        let progress = ExportServiceBatchProgressRecorder()
        let service = ExportService(exporter: exporter)
        let batch = try ExportBatch([
            makeRequest(format: .mp4),
            makeRequest(format: .hevc),
            makeRequest(format: .gif)
        ])

        let exported = try await service.runBatch(
            batch,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        ) { snapshot in
            await progress.append(snapshot)
        }

        let captured = await exporter.capturedExports()
        let snapshots = await progress.snapshots()

        #expect(exported.map(\.format) == [.mp4, .hevc, .gif])
        #expect(Set(captured.map(\.request.format)) == [.mp4, .hevc, .gif])
        #expect(
            Set(captured.map(\.outputFileURL.path)) == [
                "/tmp/exports/Luxel Clip H.264.mp4",
                "/tmp/exports/Luxel Clip HEVC.mp4",
                "/tmp/exports/Luxel Clip GIF.gif"
            ])

        let expectedFormatsByJobID: [Int: ExportFormat] = [0: .mp4, 1: .hevc, 2: .gif]
        for (jobID, format) in expectedFormatsByJobID {
            let jobSnapshots = snapshots.filter { $0.jobID == jobID }.map(\.snapshot)
            #expect(
                jobSnapshots == [
                    .preparing(format: format),
                    .exporting(format: format, progress: 0),
                    .completed(format: format)
                ])
        }
    }

}

extension ExportServiceTests {
    @Test("batch export names audio formats distinctly")
    func batchExportNamesAudioFormatsDistinctly() async throws {
        let exporter = ExportServiceSpyMediaExporter()
        let service = ExportService(exporter: exporter)
        let batch = try ExportBatch(ExportFormat.audioOnlyFormats.map { try makeRequest(format: $0) })

        _ = try await service.runBatch(
            batch,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        )

        let captured = await exporter.capturedExports()
        #expect(
            Set(captured.map(\.outputFileURL.path)) == [
                "/tmp/exports/Luxel Clip M4A AAC.m4a",
                "/tmp/exports/Luxel Clip M4A ALAC.m4a",
                "/tmp/exports/Luxel Clip WAV.wav",
                "/tmp/exports/Luxel Clip CAF.caf",
                "/tmp/exports/Luxel Clip FLAC.flac"
            ])
    }

    @Test("batch prepares Studio Voice once and supplies shared audio to every exporter")
    func batchSharesPreparedStudioVoiceAudio() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory.appending(
            path: "ExportServicePreparedAudio-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let preparedURL = temporaryDirectory.appending(path: "prepared.caf")
        try Data([0]).write(to: preparedURL)
        let preparedAsset = PreparedAudioAsset(
            fileURL: preparedURL,
            duration: 10,
            sampleRate: 48_000,
            channelCount: 2
        )
        let preparer = ExportServiceSpyExportAudioPreparer(
            preparedAsset: preparedAsset,
            temporaryDirectoryURL: temporaryDirectory
        )
        let exporter = ExportServiceSpyMediaExporter()
        let progress = ExportServiceBatchProgressRecorder()
        let service = ExportService(exporter: exporter, audioPreparer: preparer)
        let batch = try ExportBatch([
            makeRequest(format: .mp4, studioVoiceEnabled: true),
            makeRequest(format: .webm, studioVoiceEnabled: true)
        ])

        _ = try await service.runBatch(
            batch,
            to: URL(fileURLWithPath: "/tmp/exports"),
            defaultName: "Luxel Clip"
        ) { snapshot in
            await progress.append(snapshot)
        }

        let captured = await exporter.capturedExports()
        #expect(await preparer.prepareCallCount() == 1)
        #expect(captured.map(\.preparedAudio) == [preparedAsset, preparedAsset])
        #expect(
            await progress.snapshots().filter {
                $0.snapshot.phase == .enhancingAudio
            }.count == 2
        )
        #expect(!FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    @Test("request-only exporter convenience rejects untreated Studio Voice")
    func requestOnlyExporterRejectsStudioVoice() async throws {
        let exporter = ExportServiceSpyMediaExporter()
        let request = try makeRequest(format: .mp4, studioVoiceEnabled: true)

        await #expect(throws: MediaExporterError.preparedAudioRequired) {
            _ = try await exporter.export(
                request,
                to: URL(fileURLWithPath: "/tmp/untreated.mp4"),
                progress: nil
            )
        }
    }

    @Test("batch cancellation keeps completed output and removes in-flight output")
    func batchCancellationKeepsCompletedOutputAndRemovesInFlightOutput() async throws {
        let exporter = ExportServiceBatchCancellableExporter()
        let fileSystem = ExportServiceSpyFileSystem()
        let service = ExportService(exporter: exporter, fileSystem: fileSystem)
        let batch = try ExportBatch([
            makeRequest(format: .mp4),
            makeRequest(format: .gif),
            makeRequest(format: .hevc)
        ])

        let progress = ExportServiceBatchProgressRecorder()
        let task = Task {
            try await service.runBatch(
                batch,
                to: URL(fileURLWithPath: "/tmp/exports"),
                defaultName: "Luxel Clip"
            ) { snapshot in
                await progress.append(snapshot)
            }
        }

        await exporter.waitUntilHangingExportsStarted(count: 2)
        while await !progress.snapshots().contains(where: { $0.snapshot.phase == .completed }) {
            await Task.yield()
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }

        let captured = await exporter.capturedExports()
        #expect(Set(captured.map(\.request.format)) == [.mp4, .gif, .hevc])
        #expect(
            Set(fileSystem.removedURLs) == [
                URL(fileURLWithPath: "/tmp/exports/Luxel Clip GIF.gif"),
                URL(fileURLWithPath: "/tmp/exports/Luxel Clip HEVC.mp4")
            ])
    }

    private func makeSource() throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
    }

    private func makeRequest(
        format: ExportFormat,
        studioVoiceEnabled: Bool = false
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: false,
            studioVoiceEnabled: studioVoiceEnabled,
            shouldCrop: false
        )
    }
}
