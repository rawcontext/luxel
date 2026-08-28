import Foundation
import LuxelCore

private enum CommandLineExportError: LocalizedError {
    case missingInput(String)
    case outputExists(String)
    case outputIsDirectory(String)
    case unsupportedFormat(String)
    case invalidOptions(String)

    var errorDescription: String? {
        switch self {
        case .missingInput(let path): "Input file not found: \(path)"
        case .outputExists(let path):
            "Output file already exists: \(path). Use --overwrite to replace it."
        case .outputIsDirectory(let path): "Output path is a directory: \(path)"
        case .unsupportedFormat(let message), .invalidOptions(let message): message
        }
    }
}

@MainActor
extension LuxelMenuModel {
    func runCommandLineConversion(
        _ arguments: CommandLineConvertArguments
    ) async throws -> CommandLineAutomationResult {
        let input = URL(fileURLWithPath: arguments.inputPath).standardizedFileURL
        let output = URL(fileURLWithPath: arguments.outputPath).standardizedFileURL
        return try await withCommandLineFileAccess(paths: [input, output]) {
            try self.validateCommandLineInput(input)
            try self.prepareCommandLineOutput(output, overwrite: arguments.overwrite)
            let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: input)
            let request = try self.commandLineExportRequest(
                arguments,
                source: source,
                input: input,
                output: output
            )
            return try await self.performCommandLineExport(request, output: output)
        }
    }

    func runCommandLineExport(
        _ arguments: CommandLineExportArguments
    ) async throws -> CommandLineAutomationResult {
        let requestURL = URL(fileURLWithPath: arguments.requestPath).standardizedFileURL
        let output = URL(fileURLWithPath: arguments.outputPath).standardizedFileURL
        return try await withCommandLineFileAccess(paths: [requestURL, output]) {
            try self.validateCommandLineInput(requestURL)
            let request = try JSONDecoder().decode(
                ExportRequest.self,
                from: Data(contentsOf: requestURL)
            )
            return try await self.withCommandLineFileAccess(paths: [request.inputFileURL, output]) {
                try self.validateCommandLineInput(request.inputFileURL)
                try self.prepareCommandLineOutput(output, overwrite: arguments.overwrite)
                return try await self.performCommandLineExport(request, output: output)
            }
        }
    }

    private func commandLineExportRequest(
        _ arguments: CommandLineConvertArguments,
        source: SourceMedia,
        input: URL,
        output: URL
    ) throws -> ExportRequest {
        let format = try commandLineExportFormat(explicit: arguments.format, output: output)
        let quality = try commandLineExportQuality(arguments.quality, format: format)
        let pixelSize: PixelSize?
        if let width = arguments.width, let height = arguments.height {
            pixelSize = try PixelSize(width: width, height: height)
        } else {
            pixelSize = nil
        }
        let cropRect = try arguments.crop.map {
            try CaptureRect(
                x: $0.originX,
                y: $0.originY,
                width: $0.width,
                height: $0.height
            )
        }
        let trimRange = try commandLineTrimRange(arguments, duration: source.duration)
        let draft = try EditorExportDraft(
            source: source.replacingFileURL(input),
            format: format,
            quality: quality,
            speed: PlaybackSpeed(arguments.speed),
            pixelSize: pixelSize,
            frameRate: try arguments.framesPerSecond.map(FrameRate.init),
            trimRange: trimRange,
            shouldCrop: arguments.cropToFill || cropRect != nil,
            cropRect: cropRect,
            shouldMute: arguments.mute
        )
        return try draft.exportRequest
    }

    private func commandLineExportFormat(
        explicit: String?,
        output: URL
    ) throws -> ExportFormat {
        let format =
            try explicit.map { explicit in
                guard let format = ExportFormat(rawValue: explicit.lowercased()) else {
                    throw CommandLineExportError.unsupportedFormat("Unsupported format: \(explicit)")
                }
                return format
            } ?? inferredCommandLineExportFormat(output: output)

        guard output.pathExtension.lowercased() == format.fileExtension else {
            throw CommandLineExportError.invalidOptions(
                "--format \(format.rawValue) requires .\(format.fileExtension) output."
            )
        }
        return format
    }

    private func inferredCommandLineExportFormat(output: URL) throws -> ExportFormat {
        switch output.pathExtension.lowercased() {
        case "gif": .gif
        case "mp4": .mp4
        case "webm": .webm
        case "apng": .apng
        case "wav": .wav
        case "caf": .caf
        case "flac": .flac
        case "mov":
            throw CommandLineExportError.invalidOptions(
                "Use --format prores422 or --format prores4444 for .mov output."
            )
        case "m4a":
            throw CommandLineExportError.invalidOptions(
                "Use --format m4a or --format alac for .m4a output."
            )
        default:
            throw CommandLineExportError.unsupportedFormat(
                "Unsupported output extension: .\(output.pathExtension)"
            )
        }
    }

    private func commandLineExportQuality(
        _ rawValue: String?,
        format: ExportFormat
    ) throws -> ExportQuality {
        let quality: ExportQuality
        if let rawValue {
            guard let parsed = ExportQuality(rawValue: rawValue.lowercased()) else {
                throw CommandLineExportError.invalidOptions("Unsupported quality: \(rawValue)")
            }
            quality = parsed
        } else {
            quality = ExportQuality.defaultQuality(for: format)
        }
        guard quality.isAvailable(for: format) else {
            throw CommandLineExportError.invalidOptions(
                "\(quality.rawValue) quality is not available for \(format.rawValue)."
            )
        }
        return quality
    }

    private func commandLineTrimRange(
        _ arguments: CommandLineConvertArguments,
        duration: TimeInterval
    ) throws -> TimeRange? {
        let start = arguments.startSeconds ?? 0
        let end: TimeInterval
        if let requestedDuration = arguments.durationSeconds {
            end = start + requestedDuration
        } else {
            end = arguments.endSeconds ?? duration
        }
        guard start >= 0, start < duration, end > start, end <= duration + 0.000_001 else {
            throw CommandLineExportError.invalidOptions(
                "Trim range must fit within the input duration."
            )
        }
        if start == 0, abs(end - duration) < 0.000_001 { return nil }
        return try TimeRange(start: start, end: end)
    }

    private func performCommandLineExport(
        _ request: ExportRequest,
        output: URL
    ) async throws -> CommandLineAutomationResult {
        let registry = LuxelCompositionRoot.codecAdapterRegistry()
        let service = ExportService(
            exporter: registry.mediaExporter(nativeExporter: NativeMediaExporter()),
            audioPreparer: LuxelCompositionRoot.exportAudioPreparer(),
            fileSystem: LocalFileSystem()
        )
        let exported = try await service.export(
            request,
            to: output.deletingLastPathComponent(),
            defaultName: output.deletingPathExtension().lastPathComponent
        ) { _ in }
        let attributes = try? FileManager.default.attributesOfItem(atPath: exported.fileURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value
        return CommandLineAutomationResult(
            filePath: exported.fileURL.path,
            export: CommandLineExportResult(
                filePath: exported.fileURL.path,
                format: exported.format.rawValue,
                width: exported.pixelSize.width,
                height: exported.pixelSize.height,
                shouldMute: exported.shouldMute,
                fileSizeBytes: fileSize
            )
        )
    }

    private func validateCommandLineInput(_ url: URL) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw CommandLineExportError.missingInput(url.path)
        }
    }

    private func prepareCommandLineOutput(_ url: URL, overwrite: Bool) throws {
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else {
                throw CommandLineExportError.outputIsDirectory(url.path)
            }
            guard overwrite else {
                throw CommandLineExportError.outputExists(url.path)
            }
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
