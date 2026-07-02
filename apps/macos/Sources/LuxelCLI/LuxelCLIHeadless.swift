import ArgumentParser
import Foundation
import LuxelCodecWebM
import LuxelCore

public struct LuxelEditorCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "editor",
        abstract: "Open a media file in Luxel's editor."
    )

    @Argument(help: "Media file to open.", completion: .file())
    public var file: LuxelFilePath

    public init() {}

    public mutating func run() throws {
        try validateInputFile(file.url)
        try SystemLuxelEditorOpener().openEditor(fileURL: file.url)
    }
}

public struct LuxelConvertCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "convert",
        abstract: "Convert or edit media headlessly through Luxel's exporter.",
        discussion: """
      The output format is inferred from the output file extension unless --format is \
      provided. Use --format for ambiguous extensions such as .mov or .m4a.
      """
    )

    @Argument(help: "Input media file.", completion: .file())
    public var input: LuxelFilePath

    @Argument(help: "Output media file.", completion: .file())
    public var output: LuxelFilePath

    @Option(
        help:
            "Output format. Values: \(LuxelHeadlessExportFormat.allValueStrings.joined(separator: ", "))."
    )
    public var format: LuxelHeadlessExportFormat?

    @Option(help: "Output width in pixels. Must be used with --height.")
    public var width: Int?

    @Option(help: "Output height in pixels. Must be used with --width.")
    public var height: Int?

    @Option(help: "Output frame rate.")
    public var fps: Int?

    @Option(help: "Trim start time in seconds.")
    public var start: Double?

    @Option(help: "Trim end time in seconds.")
    public var end: Double?

    @Option(help: "Trim duration in seconds. Cannot be combined with --end.")
    public var duration: Double?

    @Option(help: "Playback speed from 0.1 to 10. Defaults to 1.")
    public var speed: Double = 1

    @Flag(help: "Export without audio.")
    public var mute = false

    @Flag(name: .customLong("crop-to-fill"), help: "Enable crop-to-fill rendering.")
    public var cropToFill = false

    @Option(
        name: .customLong("crop"),
        help: "Crop rectangle as x,y,width,height."
    )
    public var crop: LuxelCropRectArgument?

    @Option(help: "Export quality. Values: compact, balanced, high, lossless.")
    public var quality: LuxelExportQualityArgument?

    @Flag(help: "Replace the output file if it already exists.")
    public var overwrite = false

    @Flag(help: "Print a JSON result instead of the output path.")
    public var json = false

    @Flag(help: "Suppress terminal progress output.")
    public var quiet = false

    public init() {}

    public func exportRequest(for source: SourceMedia) throws -> ExportRequest {
        try exportDraft(for: source).exportRequest
    }

    public func exportDraft(for source: SourceMedia) throws -> EditorExportDraft {
        let resolvedFormat = try LuxelHeadlessExportFormat.resolve(
            explicit: format,
            outputURL: output.url
        )
        let resolvedQuality = try quality(for: resolvedFormat.domainValue)

        return try EditorExportDraft(
            source: source.replacingFileURL(input.url),
            format: resolvedFormat.domainValue,
            trimRange: timeRange(sourceDuration: source.duration),
            pixelSize: pixelSize(),
            frameRate: frameRate(),
            shouldMute: mute,
            shouldCrop: cropToFill || crop != nil,
            cropRect: crop?.domainValue,
            quality: resolvedQuality,
            speed: PlaybackSpeed(speed)
        )
    }

    public mutating func run() throws {
        let command = self
        try LuxelAsync.run {
            try await LuxelHeadlessExportRunner().convert(command)
        }
    }

    private func pixelSize() throws -> PixelSize? {
        switch (width, height) {
        case (.none, .none):
            return nil
        case (.some(let width), .some(let height)):
            return try PixelSize(width: width, height: height)
        default:
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use both --width and --height, or neither."
            )
        }
    }

    private func frameRate() throws -> FrameRate? {
        guard let fps else {
            return nil
        }

        return try FrameRate(fps)
    }

    private func timeRange(sourceDuration: TimeInterval) throws -> TimeRange? {
        if end != nil, duration != nil {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "--end and --duration cannot be combined."
            )
        }

        let resolvedStart = try validatedNonNegative(start ?? 0, name: "--start")
        let resolvedEnd: TimeInterval
        if let duration {
            let resolvedDuration = try validatedPositive(duration, name: "--duration")
            resolvedEnd = resolvedStart + resolvedDuration
        } else if let end {
            resolvedEnd = try validatedPositive(end, name: "--end")
        } else {
            resolvedEnd = sourceDuration
        }

        guard resolvedStart < sourceDuration, resolvedEnd <= sourceDuration + 0.000_001 else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Trim range must fit within the input duration."
            )
        }

        if resolvedStart == 0, abs(resolvedEnd - sourceDuration) < 0.000_001 {
            return nil
        }

        return try TimeRange(start: resolvedStart, end: resolvedEnd)
    }

    private func quality(for format: ExportFormat) throws -> ExportQuality {
        let resolvedQuality = quality?.domainValue ?? ExportQuality.defaultQuality(for: format)
        guard resolvedQuality.isAvailable(for: format) else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "\(resolvedQuality.rawValue) quality is not available for \(format.rawValue)."
            )
        }

        return resolvedQuality
    }
}

public struct LuxelExportCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export media from a full Luxel ExportRequest JSON document.",
        discussion: """
      This command is the escape hatch for editor/export fields that do not have \
      dedicated CLI flags. The request JSON uses LuxelCore's ExportRequest shape.
      """
    )

    @Argument(help: "ExportRequest JSON file.", completion: .file())
    public var request: LuxelFilePath

    @Argument(help: "Output media file.", completion: .file())
    public var output: LuxelFilePath

    @Flag(help: "Replace the output file if it already exists.")
    public var overwrite = false

    @Flag(help: "Print a JSON result instead of the output path.")
    public var json = false

    @Flag(help: "Suppress terminal progress output.")
    public var quiet = false

    public init() {}

    public mutating func run() throws {
        let command = self
        try LuxelAsync.run {
            try await LuxelHeadlessExportRunner().export(command)
        }
    }
}

public struct LuxelTranscribeCommand: ParsableCommand, Sendable {
    public static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Transcribe a media file with Luxel's local transcript service.",
        discussion: """
      Text is printed to stdout by default, so shell redirection works:
      luxel transcribe recording.m4a > recording.txt
      """
    )

    @Argument(help: "Media or audio file to transcribe.", completion: .file())
    public var file: LuxelFilePath

    @Option(help: "Locale identifier. Defaults to the current locale.")
    public var locale: String?

    @Option(help: "Write transcript output to a file instead of stdout.", completion: .file())
    public var output: LuxelFilePath?

    @Flag(name: .customLong("semantic-turns"), help: "Use Apple Intelligence turn segmentation.")
    public var semanticTurns = false

    @Flag(help: "Print the full transcript JSON instead of plain text.")
    public var json = false

    @Flag(help: "Replace --output if it already exists.")
    public var overwrite = false

    public init() {}

    public mutating func run() throws {
        let command = self
        try LuxelAsync.run {
            try await LuxelTranscriptionRunner().transcribe(command)
        }
    }
}

public struct LuxelFilePath: ExpressibleByArgument, Hashable, Sendable {
    public let url: URL

    public init?(argument: String) {
        let expandedPath = (argument as NSString).expandingTildeInPath
        if let url = URL(string: expandedPath),
           url.scheme != nil {
            guard url.isFileURL else {
                return nil
            }

            self.url = url.standardizedFileURL
        } else {
            self.url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        }
    }

    public static var defaultCompletionKind: CompletionKind {
        .file()
    }
}

public enum LuxelHeadlessExportFormat: String, CaseIterable, ExpressibleByArgument, Sendable {
    case gif
    case hevc
    case mp4
    case webm
    case apng
    case proRes422 = "prores422"
    case proRes4444 = "prores4444"
    case m4a
    case alac
    case wav
    case caf
    case flac

    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }

    public var domainValue: ExportFormat {
        switch self {
        case .gif:
            .gif
        case .hevc:
            .hevc
        case .mp4:
            .mp4
        case .webm:
            .webm
        case .apng:
            .apng
        case .proRes422:
            .proRes422
        case .proRes4444:
            .proRes4444
        case .m4a:
            .m4a
        case .alac:
            .alac
        case .wav:
            .wav
        case .caf:
            .caf
        case .flac:
            .flac
        }
    }

    public static func resolve(
        explicit: LuxelHeadlessExportFormat?,
        outputURL: URL
    ) throws -> LuxelHeadlessExportFormat {
        if let explicit {
            try validateOutputExtension(outputURL, format: explicit)
            return explicit
        }

        let outputExtension = outputURL.pathExtension.lowercased()
        switch outputExtension {
        case "gif":
            return .gif
        case "mp4":
            return .mp4
        case "webm":
            return .webm
        case "apng":
            return .apng
        case "wav":
            return .wav
        case "caf":
            return .caf
        case "flac":
            return .flac
        case "mov":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use --format prores422 or --format prores4444 for .mov output."
            )
        case "m4a":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Use --format m4a or --format alac for .m4a output."
            )
        case "":
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Output path must include a file extension."
            )
        default:
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Unsupported output extension .\(outputExtension). Use --format with a supported extension."
            )
        }
    }

    private static func validateOutputExtension(
        _ outputURL: URL,
        format: LuxelHeadlessExportFormat
    ) throws {
        let expectedExtension = format.domainValue.fileExtension
        guard outputURL.pathExtension.lowercased() == expectedExtension else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "--format \(format.rawValue) requires .\(expectedExtension) output."
            )
        }
    }
}

public enum LuxelExportQualityArgument: String, CaseIterable, ExpressibleByArgument, Sendable {
    case compact
    case balanced
    case high
    case lossless

    public static var allValueStrings: [String] {
        allCases.map(\.rawValue)
    }

    public var domainValue: ExportQuality {
        switch self {
        case .compact:
            .compact
        case .balanced:
            .balanced
        case .high:
            .high
        case .lossless:
            .lossless
        }
    }
}

public struct LuxelCropRectArgument: ExpressibleByArgument, Equatable, Sendable {
    public let domainValue: CaptureRect

    public init?(argument: String) {
        let components = argument.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard components.count == 4,
              let originX = Int(components[0]),
              let originY = Int(components[1]),
              let width = Int(components[2]),
              let height = Int(components[3]),
              let rect = try? CaptureRect(x: originX, y: originY, width: width, height: height)
        else {
            return nil
        }

        domainValue = rect
    }
}

public protocol LuxelEditorOpener: Sendable {
    func openEditor(fileURL: URL) throws
}

public struct SystemLuxelEditorOpener: LuxelEditorOpener {
    public init() {}

    public func openEditor(fileURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = openArguments(fileURL: fileURL)
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw LuxelCLIError.openFailed(process.terminationStatus)
        }
    }

    public func openArguments(fileURL: URL) -> [String] {
        if let appBundleURL = Self.containingAppBundleURL() {
            return ["-a", appBundleURL.path, fileURL.path]
        }

        return ["-b", "media.luxel.app", fileURL.path]
    }

    public static func containingAppBundleURL(
        executableURL: URL? = Bundle.main.executableURL
    ) -> URL? {
        guard var directory = executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        else {
            return nil
        }

        for _ in 0..<8 {
            if directory.pathExtension == "app" {
                return directory
            }

            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else {
                return nil
            }
            directory = parent
        }

        return nil
    }
}

public struct LuxelHeadlessExportResult: Codable, Equatable, Sendable {
    public let filePath: String
    public let format: String
    public let width: Int
    public let height: Int
    public let shouldMute: Bool
    public let fileSizeBytes: Int64?

    public init(exportedMedia: ExportedMedia) {
        filePath = exportedMedia.fileURL.path
        format = exportedMedia.format.rawValue
        width = exportedMedia.pixelSize.width
        height = exportedMedia.pixelSize.height
        shouldMute = exportedMedia.shouldMute
        fileSizeBytes = exportedMedia.fileSizeBytes
    }
}

public enum LuxelTranscriptFormatter {
    public static func plainText(_ transcript: TurnSegmentedTranscript) -> String {
        transcript.turns.map(\.text).joined(separator: "\n")
    }

    public static func data(
        for transcript: TurnSegmentedTranscript,
        json: Bool
    ) throws -> Data {
        let data: Data
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(transcript)
        } else {
            data = Data(plainText(transcript).utf8)
        }

        return data.withTrailingNewline()
    }
}

private struct LuxelHeadlessExportRunner: Sendable {
    func convert(_ command: LuxelConvertCommand) async throws {
        try validateInputFile(command.input.url)
        try prepareOutputFile(command.output.url, overwrite: command.overwrite)

        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: command.input.url)
        let request = try command.exportRequest(for: source)
        let result = try await export(
            request,
            to: command.output.url,
            showProgress: !command.quiet
        )
        try printExportResult(result, json: command.json)
    }

    func `export`(_ command: LuxelExportCommand) async throws {
        try validateInputFile(command.request.url)
        try prepareOutputFile(command.output.url, overwrite: command.overwrite)

        let requestData = try Data(contentsOf: command.request.url)
        let request = try JSONDecoder().decode(ExportRequest.self, from: requestData)
        let result = try await export(
            request,
            to: command.output.url,
            showProgress: !command.quiet
        )
        try printExportResult(result, json: command.json)
    }

    private func export(
        _ request: ExportRequest,
        to outputURL: URL,
        showProgress: Bool
    ) async throws -> LuxelHeadlessExportResult {
        let registry = try CodecAdapterRegistry(registrations: [try WebMCodecAdapter.registration()])
        let exporter = registry.mediaExporter(nativeExporter: NativeMediaExporter())
        let progress = LuxelTerminalProgressReporter(
            label: "Exporting \(request.format.prettyName)",
            isEnabled: showProgress && LuxelTerminalProgressReporter.defaultIsEnabled
        )

        progress.start()
        do {
            let exported = try await exporter.export(request, to: outputURL) { value in
                progress.update(value)
            }
            progress.finish()
            return LuxelHeadlessExportResult(
                exportedMedia: exported.withFileSizeBytes(fileSizeBytes(at: outputURL))
            )
        } catch {
            progress.fail()
            throw error
        }
    }

    private func printExportResult(_ result: LuxelHeadlessExportResult, json: Bool) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result).withTrailingNewline())
        } else {
            print(result.filePath)
        }
    }
}

private struct LuxelTranscriptionRunner: Sendable {
    func transcribe(_ command: LuxelTranscribeCommand) async throws {
        try validateInputFile(command.file.url)
        if let output = command.output {
            try prepareOutputFile(output.url, overwrite: command.overwrite)
        }

        guard await AppleSpeechRecognitionAuthorizationService().requestAuthorization() == .authorized
        else {
            throw LuxelCLIError.speechRecognitionDenied
        }

        let mode: TranscriptTurnSegmentationMode = command.semanticTurns ? .semantic : .raw
        let transcript = try await transcriptService(mode: mode).transcript(
            for: AudioTranscriptRequest(
                audioURL: command.file.url,
                locale: Locale(identifier: command.locale ?? Locale.current.identifier),
                sourceContext: .unknown,
                turnSegmentationMode: mode
            )
        )

        guard let transcript else {
            throw LuxelCLIError.transcriptUnavailable
        }

        let data = try LuxelTranscriptFormatter.data(for: transcript, json: command.json)
        if let output = command.output {
            try data.write(to: output.url, options: .atomic)
        } else {
            FileHandle.standardOutput.write(data)
        }
    }

    private func transcriptService(mode: TranscriptTurnSegmentationMode)
    -> LocalAudioTranscriptService {
        let semanticSegmenter: any TranscriptTurnSegmenter =
            mode == .semantic ? AppleIntelligenceTurnSegmenter() : RawTranscriptTurnSegmenter()

        return LocalAudioTranscriptService(
            transcriber: AppleSpeechTranscriptExtractor(),
            turnSegmenter: semanticSegmenter,
            turnSegmentationMode: { mode },
            cache: ApplicationSupportTranscriptCache(cacheDirectory: transcriptCacheDirectory()),
            audioTrackInspector: AVFoundationAudioTrackInspector()
        )
    }

    private func transcriptCacheDirectory() -> URL {
        let applicationSupport =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                "Library/Application Support")

        return
            applicationSupport
            .appendingPathComponent("Luxel", isDirectory: true)
            .appendingPathComponent("Transcripts", isDirectory: true)
    }
}

private enum LuxelAsync {
    static func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let box = LuxelAsyncResultBox<T>()

        Task {
            do {
                box.resolve(.success(try await operation()))
            } catch {
                box.resolve(.failure(error))
            }
        }

        return try box.wait().get()
    }
}

private final class LuxelAsyncResultBox<T: Sendable>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var result: Result<T, any Error>?

    func resolve(_ result: Result<T, any Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> Result<T, any Error> {
        semaphore.wait()
        lock.lock()
        defer {
            lock.unlock()
        }

        return result
            ?? .failure(LuxelCLIError.remoteFailure("Async command did not produce a result."))
    }
}

private func validateInputFile(_ url: URL) throws {
    var isDirectory = ObjCBool(false)
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue
    else {
        throw LuxelCLIError.fileNotFound(url.path)
    }
}

private func prepareOutputFile(_ url: URL, overwrite: Bool) throws {
    var isDirectory = ObjCBool(false)
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        guard !isDirectory.boolValue else {
            throw LuxelCLIError.invalidHeadlessExportOptions(
                "Output path is a directory: \(url.path)"
            )
        }
        guard overwrite else {
            throw LuxelCLIError.outputFileExists(url.path)
        }
    }

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
}

private func fileSizeBytes(at url: URL) -> Int64? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attributes[.size] as? NSNumber
    else {
        return nil
    }

    return size.int64Value
}

private func validatedNonNegative(_ value: Double, name: String) throws -> Double {
    guard value.isFinite, value >= 0 else {
        throw LuxelCLIError.invalidHeadlessExportOptions("\(name) must be zero or greater.")
    }

    return value
}

private func validatedPositive(_ value: Double, name: String) throws -> Double {
    guard value.isFinite, value > 0 else {
        throw LuxelCLIError.invalidHeadlessExportOptions("\(name) must be greater than zero.")
    }

    return value
}

extension Data {
    fileprivate func withTrailingNewline() -> Data {
        guard last != 0x0A else {
            return self
        }

        var data = self
        data.append(0x0A)
        return data
    }
}
